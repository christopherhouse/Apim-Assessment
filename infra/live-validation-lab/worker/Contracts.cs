using System.Globalization;
using System.Net;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace LabWorker;

internal sealed record WorkerConfig(
    string SchemaVersion,
    string TenantId,
    string BackendAudienceClientId,
    string[] BackendCallerClientIds,
    string FrontendResourceClientId,
    string BackendOrigin,
    string ApimOrigin,
    string GatewayOrigin)
{
    internal const string BackendRole = "Lab.Backend.Invoke";
    internal string Issuer => $"https://login.microsoftonline.com/{TenantId}/v2.0";

    internal static WorkerConfig Parse(string text)
    {
        var config = StrictJson.Read<WorkerConfig>(text);
        if (config.SchemaVersion != "1.0" || !IsId(config.TenantId) ||
            !IsId(config.BackendAudienceClientId) || !IsId(config.FrontendResourceClientId) ||
            config.BackendAudienceClientId == config.FrontendResourceClientId ||
            config.BackendCallerClientIds is not { Length: >= 1 and <= 2 } ||
            config.BackendCallerClientIds.Any(id => !IsId(id)) ||
            config.BackendCallerClientIds.Distinct(StringComparer.Ordinal).Count() != config.BackendCallerClientIds.Length)
            throw new InvalidDataException("InvalidWorkerConfiguration");
        foreach (var origin in new[] { config.BackendOrigin, config.ApimOrigin, config.GatewayOrigin })
        {
            if (origin is null || origin.Length > 261 ||
                !Regex.IsMatch(origin, @"^https://(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$",
                    RegexOptions.CultureInvariant | RegexOptions.NonBacktracking) ||
                !Uri.TryCreate(origin, UriKind.Absolute, out var uri) || uri.HostNameType != UriHostNameType.Dns)
                throw new InvalidDataException("InvalidWorkerOrigin");
        }
        if (new[] { config.BackendOrigin, config.ApimOrigin, config.GatewayOrigin }.Distinct(StringComparer.Ordinal).Count() != 3)
            throw new InvalidDataException("ConflictingWorkerOrigins");
        return config;
    }

    private static bool IsId(string? value) =>
        Guid.TryParseExact(value, "D", out var id) && id != Guid.Empty && value == id.ToString("D");
}

internal sealed record WorkerPaths(string Config, string Certificate, string Key, string StateDirectory, string Scenarios)
{
    internal string Job => Path.Combine(StateDirectory, "request.json");
    internal string Lock => Path.Combine(StateDirectory, "job.lock");
    internal string Fault => Path.Combine(StateDirectory, "fault.json");
    internal string FaultCounter => Path.Combine(StateDirectory, "runtime", "fault-counter.json");
    internal static WorkerPaths Installed => new(
        "/etc/apim-lab-worker/config.json", "/etc/apim-lab-worker/tls/cert.pem",
        "/etc/apim-lab-worker/tls/key.pem", "/var/lib/apim-lab-worker",
        Path.Combine(AppContext.BaseDirectory, "scenarios"));
}

internal static class StrictJson
{
    internal static readonly JsonSerializerOptions Options = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = false,
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow,
        RespectRequiredConstructorParameters = true,
        MaxDepth = 16
    };

    internal static T Read<T>(string text)
    {
        using var document = Document(text);
        return document.RootElement.Deserialize<T>(Options) ?? throw new InvalidDataException("MissingJsonValue");
    }

    internal static JsonDocument Document(string text)
    {
        var document = JsonDocument.Parse(text, new JsonDocumentOptions { MaxDepth = 16 });
        try { Check(document.RootElement); return document; }
        catch { document.Dispose(); throw; }
    }

    private static void Check(JsonElement element)
    {
        if (element.ValueKind == JsonValueKind.Object)
        {
            var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var property in element.EnumerateObject())
            {
                if (!names.Add(property.Name)) throw new InvalidDataException("DuplicateJsonProperty");
                Check(property.Value);
            }
        }
        else if (element.ValueKind == JsonValueKind.Array)
            foreach (var item in element.EnumerateArray()) Check(item);
    }
}

internal static class PrivateFiles
{
    internal static void CheckPath(string path)
    {
        if (!Path.IsPathFullyQualified(path)) throw new InvalidDataException("PrivatePathRequired");
        var current = Path.GetFullPath(path);
        while (!string.IsNullOrEmpty(current))
        {
            if (File.Exists(current) || Directory.Exists(current))
            {
                var info = new FileInfo(current);
                if ((info.Attributes & FileAttributes.ReparsePoint) != 0 || info.LinkTarget is not null)
                    throw new InvalidDataException("LinkedPrivatePath");
            }
            current = Path.GetDirectoryName(current);
        }
    }

    internal static string Read(string path, int maxBytes = 16_384)
    {
        CheckPath(path);
        if (OperatingSystem.IsLinux() || OperatingSystem.IsMacOS())
        {
            var mode = File.GetUnixFileMode(path);
            if ((mode & (UnixFileMode.OtherRead | UnixFileMode.OtherWrite | UnixFileMode.OtherExecute |
                         UnixFileMode.GroupWrite | UnixFileMode.GroupExecute)) != 0)
                throw new InvalidDataException("PrivateFilePermissions");
        }
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        if (stream.Length > maxBytes) throw new InvalidDataException("PrivateInputTooLarge");
        using var reader = new StreamReader(stream, new System.Text.UTF8Encoding(false, true));
        return reader.ReadToEnd();
    }

    internal static void WriteFault(string path, FaultProfile profile)
    {
        CheckPath(path);
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            var options = new FileStreamOptions { Mode = FileMode.CreateNew, Access = FileAccess.Write, Share = FileShare.None };
            if (!OperatingSystem.IsWindows())
                options.UnixCreateMode = UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.GroupRead;
            using (var stream = new FileStream(temporary, options))
            {
                JsonSerializer.Serialize(stream, profile, StrictJson.Options);
                stream.Flush(true);
            }
            File.Move(temporary, path, true);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
}

internal sealed record JobRequest(string Kind, string? Profile = null, int RequestCount = 0,
    int IntervalMilliseconds = 0, int DurationSeconds = 0, int DelayMilliseconds = 0, int FailureCount = 0)
{
    internal void Validate()
    {
        var valid = Kind switch
        {
            "readiness" or "clearFault" => Profile is null && RequestCount == 0 &&
                IntervalMilliseconds == 0 && DurationSeconds == 0 && DelayMilliseconds == 0 && FailureCount == 0,
            "traffic" => Profile is not null && TrafficProfiles.All.ContainsKey(Profile) &&
                RequestCount is >= 1 and <= 20 && IntervalMilliseconds is >= 250 and <= 2000 &&
                DurationSeconds == 0 && DelayMilliseconds == 0 && FailureCount == 0,
            "fault" => Profile is null && RequestCount == 0 && IntervalMilliseconds == 0 &&
                DurationSeconds is >= 1 and <= 120 && DelayMilliseconds is >= 0 and <= 1000 &&
                FailureCount is >= 0 and <= 10 && (DelayMilliseconds > 0 || FailureCount > 0),
            _ => false
        };
        if (!valid) throw new InvalidDataException("InvalidJobBounds");
    }

    internal static JobRequest Parse(string text)
    {
        using var document = StrictJson.Document(text);
        var root = document.RootElement;
        if (root.ValueKind != JsonValueKind.Object || root.GetProperty("schemaVersion").GetString() != "1.0")
            throw new InvalidDataException("InvalidJobVersion");
        var kind = root.GetProperty("kind").GetString();
        string[] fields = kind switch
        {
            "readiness" or "clearFault" => ["schemaVersion", "kind"],
            "traffic" => ["schemaVersion", "kind", "profile", "requestCount", "intervalMilliseconds"],
            "fault" => ["schemaVersion", "kind", "durationSeconds", "delayMilliseconds", "failureCount"],
            _ => throw new InvalidDataException("UnknownJob")
        };
        if (root.EnumerateObject().Select(p => p.Name).Except(fields, StringComparer.Ordinal).Any() ||
            fields.Any(field => !root.TryGetProperty(field, out _)))
            throw new InvalidDataException("InvalidJobFields");
        if (kind == "traffic")
        {
            var profile = root.GetProperty("profile").GetString();
            var count = root.GetProperty("requestCount").GetInt32();
            var interval = root.GetProperty("intervalMilliseconds").GetInt32();
            var job = new JobRequest(kind, profile, count, interval);
            job.Validate();
            return job;
        }
        if (kind == "fault")
        {
            var duration = root.GetProperty("durationSeconds").GetInt32();
            var delay = root.GetProperty("delayMilliseconds").GetInt32();
            var failures = root.GetProperty("failureCount").GetInt32();
            var job = new JobRequest(kind, DurationSeconds: duration, DelayMilliseconds: delay, FailureCount: failures);
            job.Validate();
            return job;
        }
        return new(kind!);
    }
}

internal sealed record FaultProfile(string SchemaVersion, string ProfileId, DateTimeOffset CreatedUtc,
    DateTimeOffset ExpiresUtc, int DelayMilliseconds, int FailureCount)
{
    internal void Validate(DateTimeOffset now)
    {
        if (SchemaVersion != "1.0" || !Guid.TryParseExact(ProfileId, "D", out _) ||
            CreatedUtc.Offset != TimeSpan.Zero || ExpiresUtc.Offset != TimeSpan.Zero ||
            CreatedUtc > now.AddSeconds(5) || ExpiresUtc <= CreatedUtc || ExpiresUtc - CreatedUtc > TimeSpan.FromSeconds(120) ||
            DelayMilliseconds is < 0 or > 1000 || FailureCount is < 0 or > 10)
            throw new InvalidDataException("InvalidFaultState");
    }
}

internal sealed record JobResult(string State, string Code)
{
    internal static JobResult Ready => new("Ready", "LAB_WORKER_JOB_READY");
    internal static JobResult NotReady => new("NotReady", "LAB_WORKER_JOB_NOT_READY");
    internal static JobResult Failed => new("Failed", "LAB_WORKER_JOB_FAILED");
}
