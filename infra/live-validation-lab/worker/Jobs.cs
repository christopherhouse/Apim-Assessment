using System.Globalization;
using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace LabWorker;

internal sealed record TrafficProfile(string Origin, string Path, int ExpectedStatus, bool Authenticate);

internal static class TrafficProfiles
{
    internal static readonly IReadOnlyDictionary<string, TrafficProfile> All =
        new Dictionary<string, TrafficProfile>(StringComparer.Ordinal)
        {
            ["supply-chain"] = new("gateway", "/supply-chain/inventory", 200, true),
            ["e-commerce"] = new("gateway", "/e-commerce/products", 200, true),
            ["service-management"] = new("gateway", "/service-management/tickets/TKT-1001", 200, true),
            ["plm-private"] = new("apim", "/plm/parts/PART-1001/revisions/A", 200, true),
            ["unmatched-denied"] = new("gateway", "/not-a-lab-api", 403, false),
            ["public-plm-denied"] = new("gateway", "/plm/parts/PART-1001/revisions/A", 403, true)
        };
}

internal sealed class Jobs(WorkerConfig config, WorkerPaths paths, HttpClient client, TimeProvider clock)
{
    internal static HttpClient CreateClient() => new(new HttpClientHandler
    {
        AllowAutoRedirect = false, UseProxy = false, MaxConnectionsPerServer = 2, MaxResponseHeadersLength = 8
    })
    { Timeout = TimeSpan.FromSeconds(3) };

    internal async Task<JobResult> Run(JobRequest job, CancellationToken cancellation = default)
    {
        try
        {
            job.Validate();
            cancellation.ThrowIfCancellationRequested();
            PrivateFiles.CheckPath(paths.Lock);
            using var serial = new FileStream(paths.Lock, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            if (job.Kind == "fault")
            {
                var now = clock.GetUtcNow();
                var profile = new FaultProfile("1.0", Guid.NewGuid().ToString("D"), now,
                    now.AddSeconds(job.DurationSeconds), job.DelayMilliseconds, job.FailureCount);
                profile.Validate(now);
                PrivateFiles.WriteFault(paths.Fault, profile);
                return JobResult.Ready;
            }
            if (job.Kind == "clearFault")
            {
                PrivateFiles.CheckPath(paths.Fault);
                if (File.Exists(paths.Fault)) File.Delete(paths.Fault);
                return JobResult.Ready;
            }
            using var budget = new CancellationTokenSource(TimeSpan.FromSeconds(60), clock);
            using var linked = CancellationTokenSource.CreateLinkedTokenSource(budget.Token, cancellation);
            var token = linked.Token;
            if (job.Kind == "readiness")
                return await Probe(new Uri(config.BackendOrigin + "/healthz"), null, 200, token, readiness: true)
                    ? JobResult.Ready : JobResult.NotReady;
            if (job.Kind != "traffic" || job.Profile is null ||
                !TrafficProfiles.All.TryGetValue(job.Profile, out var route)) return JobResult.Failed;
            var origin = route.Origin == "apim" ? config.ApimOrigin : config.GatewayOrigin;
            var bearer = route.Authenticate ? await GetToken(token) : null;
            if (route.Authenticate && bearer is null) return JobResult.NotReady;
            for (var index = 0; index < job.RequestCount; index++)
            {
                if (index > 0) await Task.Delay(TimeSpan.FromMilliseconds(job.IntervalMilliseconds), clock, token);
                if (!await Probe(new Uri(origin + route.Path), bearer, route.ExpectedStatus, token))
                    return JobResult.NotReady;
            }
            return JobResult.Ready;
        }
        catch (OperationCanceledException) { return JobResult.NotReady; }
        catch (HttpRequestException) { return JobResult.NotReady; }
        catch { return JobResult.Failed; }
    }

    private async Task<bool> Probe(Uri uri, string? token, int expected, CancellationToken cancellation, bool readiness = false)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, uri);
        if (token is not null) request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellation);
        if ((int)response.StatusCode != expected || response.Content.Headers.ContentLength is > 16_384) return false;
        if (!readiness) return true;
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(3), clock);
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellation, timeout.Token);
        using var stream = await response.Content.ReadAsStreamAsync(linked.Token);
        var data = new byte[1025];
        var length = 0;
        int read;
        while (length < data.Length && (read = await stream.ReadAsync(data.AsMemory(length), linked.Token)) > 0) length += read;
        if (length >= data.Length) return false;
        using var document = StrictJson.Document(System.Text.Encoding.UTF8.GetString(data, 0, length));
        var root = document.RootElement;
        return root.ValueKind == JsonValueKind.Object && root.EnumerateObject().Count() == 2 &&
            root.GetProperty("state").GetString() == "Ready" &&
            root.GetProperty("code").GetString() == "LAB_WORKER_BACKEND_READY";
    }

    private async Task<string?> GetToken(CancellationToken cancellation)
    {
        var resource = "api://" + config.FrontendResourceClientId;
        using var request = new HttpRequestMessage(HttpMethod.Get,
            "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=" + Uri.EscapeDataString(resource));
        request.Headers.Add("Metadata", "true");
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(3), clock);
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellation, timeout.Token);
        using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, linked.Token);
        if (response.StatusCode != HttpStatusCode.OK || response.Content.Headers.ContentLength is > 32_768) return null;
        using var stream = await response.Content.ReadAsStreamAsync(linked.Token);
        using var buffer = new MemoryStream();
        var block = new byte[4096];
        int count;
        while ((count = await stream.ReadAsync(block, linked.Token)) > 0)
        {
            if (buffer.Length + count > 32_768) return null;
            buffer.Write(block, 0, count);
        }
        using var document = StrictJson.Document(System.Text.Encoding.UTF8.GetString(buffer.ToArray()));
        var root = document.RootElement;
        var token = root.GetProperty("access_token").GetString();
        if (root.GetProperty("token_type").GetString() != "Bearer" ||
            !long.TryParse(root.GetProperty("expires_on").GetString(), NumberStyles.None,
                CultureInfo.InvariantCulture, out var expiry) ||
            expiry <= clock.GetUtcNow().AddSeconds(60).ToUnixTimeSeconds() ||
            token is null || token.Length > 16_384 ||
            !Regex.IsMatch(token, @"^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$",
                RegexOptions.CultureInvariant | RegexOptions.NonBacktracking))
            return null;
        return token;
    }
}
