using System.Globalization;
using System.Net;
using System.Net.Security;
using System.Security.Authentication;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Server.Kestrel.Https;
using Microsoft.IdentityModel.Protocols;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;
using Microsoft.IdentityModel.Tokens;

namespace LabWorker;

internal static class Backend
{
    internal static WebApplication Build(WorkerConfig config, WorkerPaths paths,
        IPAddress? address = null, int port = 443,
        IConfigurationManager<OpenIdConnectConfiguration>? discovery = null, TimeProvider? clock = null)
    {
        clock ??= TimeProvider.System;
        var certificate = LoadCertificate(config, paths, clock.GetUtcNow());
        var chain = new X509Certificate2Collection();
        chain.ImportFromPem(PrivateFiles.Read(paths.Certificate, 65_536));
        var tlsContext = SslStreamCertificateContext.Create(certificate, chain, offline: true);
        var operations = SyntheticOperations.Load(paths.Scenarios);
        var fault = new FaultControl(paths, clock);
        var builder = WebApplication.CreateSlimBuilder(new WebApplicationOptions { Args = [] });
        builder.Configuration.Sources.Clear();
        builder.Logging.ClearProviders();
        builder.WebHost.ConfigureKestrel(options =>
        {
            options.AddServerHeader = false;
            options.Limits.MaxRequestBodySize = 16_384;
            options.Limits.MaxRequestLineSize = 2048;
            options.Limits.MaxRequestHeadersTotalSize = 8192;
            options.Limits.MaxConcurrentConnections = 16;
            options.Limits.RequestHeadersTimeout = TimeSpan.FromSeconds(10);
            options.Listen(address ?? IPAddress.Any, port, listen => listen.UseHttps(new HttpsConnectionAdapterOptions
            {
                ServerCertificate = certificate,
                SslProtocols = SslProtocols.Tls12 | SslProtocols.Tls13,
                OnAuthenticate = (_, authentication) => authentication.ServerCertificateContext = tlsContext
            }));
        });
        builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddJwtBearer(options =>
        {
            options.Authority = config.Issuer;
            options.RequireHttpsMetadata = true;
            options.MapInboundClaims = false;
            options.IncludeErrorDetails = false;
            options.BackchannelTimeout = TimeSpan.FromSeconds(3);
            if (discovery is not null) options.ConfigurationManager = discovery;
            options.TokenValidationParameters = new TokenValidationParameters
            {
                ValidateIssuer = true, ValidIssuer = config.Issuer,
                ValidateAudience = true, ValidAudience = config.BackendAudienceClientId,
                ValidateIssuerSigningKey = true, RequireSignedTokens = true,
                ValidateLifetime = true, RequireExpirationTime = true,
                ClockSkew = TimeSpan.FromSeconds(30),
                ValidAlgorithms = [SecurityAlgorithms.RsaSha256], ValidTypes = ["JWT"],
                RoleClaimType = "roles", NameClaimType = "azp"
            };
            options.Events = new JwtBearerEvents
            {
                OnChallenge = async context =>
                {
                    context.HandleResponse();
                    context.Response.StatusCode = StatusCodes.Status401Unauthorized;
                    context.Response.Headers.WWWAuthenticate = "Bearer";
                    await context.Response.WriteAsJsonAsync(new { code = "unauthorized", message = "Lab authentication required." });
                },
                OnForbidden = context => Error(context.Response, 403, "forbidden")
            };
        });
        builder.Services.AddAuthorizationBuilder().AddPolicy("Backend", policy =>
            policy.RequireAuthenticatedUser().RequireClaim("tid", config.TenantId).RequireClaim("ver", "2.0")
                .RequireRole(WorkerConfig.BackendRole)
                .RequireAssertion(context => !context.User.HasClaim(c => c.Type == "scp") &&
                    context.User.FindFirst("azp") is { } caller &&
                    config.BackendCallerClientIds.Contains(caller.Value, StringComparer.Ordinal)));
        var app = builder.Build();
        app.Use(async (context, next) =>
        {
            context.Response.Headers.CacheControl = "no-store";
            context.Response.Headers.XContentTypeOptions = "nosniff";
            try { await next(context); }
            catch (OperationCanceledException) when (context.RequestAborted.IsCancellationRequested) { context.Abort(); }
            catch
            {
                if (!context.Response.HasStarted) await Error(context.Response, 503, "notReady");
                else context.Abort();
            }
        });
        app.UseAuthentication();
        app.UseAuthorization();
        app.MapGet("/healthz", () => Results.Json(new { state = "Ready", code = "LAB_WORKER_BACKEND_READY" }));
        app.Map("/deny/{**path}", context => Error(context.Response, 403, "denied"));
        foreach (var operation in operations)
        {
            app.MapMethods(operation.Route, [operation.Method], async context =>
            {
                if (!await operation.Accepts(context.Request))
                {
                    await Error(context.Response, 400, "invalidRequest");
                    return;
                }
                if (operation.ApiId == "service-management")
                {
                    var (delay, fail) = fault.Next();
                    if (delay > 0) await Task.Delay(TimeSpan.FromMilliseconds(delay), clock, context.RequestAborted);
                    if (fail) { await Error(context.Response, 503, "syntheticFailure"); return; }
                }
                context.Response.StatusCode = operation.StatusCode;
                await context.Response.WriteAsJsonAsync(operation.Response, context.RequestAborted);
            }).RequireAuthorization("Backend");
        }
        app.MapFallback(context => Error(context.Response, 403, "denied"));
        app.Lifetime.ApplicationStopped.Register(() =>
        {
            certificate.Dispose();
            foreach (var item in chain) item.Dispose();
        });
        return app;
    }

    private static X509Certificate2 LoadCertificate(WorkerConfig config, WorkerPaths paths, DateTimeOffset now)
    {
        var certificate = X509Certificate2.CreateFromPem(
            PrivateFiles.Read(paths.Certificate, 65_536), PrivateFiles.Read(paths.Key));
        try
        {
            using var rsa = certificate.GetRSAPublicKey();
            using var ec = certificate.GetECDsaPublicKey();
            if (!certificate.HasPrivateKey || now.UtcDateTime < certificate.NotBefore.ToUniversalTime() ||
                now.UtcDateTime >= certificate.NotAfter.ToUniversalTime() ||
                !certificate.MatchesHostname(new Uri(config.BackendOrigin).DnsSafeHost, false, false) ||
                rsa is not null && rsa.KeySize < 2048 || ec is not null && ec.KeySize < 256 ||
                rsa is null && ec is null ||
                certificate.SignatureAlgorithm.Value is "1.2.840.113549.1.1.4" or "1.2.840.113549.1.1.5")
                throw new InvalidDataException("InvalidBackendCertificate");
            if (OperatingSystem.IsWindows())
            {
                // Schannel cannot serve a PEM-loaded ephemeral private key.
                var encoded = certificate.Export(X509ContentType.Pkcs12);
                try
                {
                    var compatible = X509CertificateLoader.LoadPkcs12(encoded, null, X509KeyStorageFlags.UserKeySet);
                    certificate.Dispose();
                    return compatible;
                }
                finally { CryptographicOperations.ZeroMemory(encoded); }
            }
            return certificate;
        }
        catch { certificate.Dispose(); throw; }
    }

    private static Task Error(HttpResponse response, int status, string code)
    {
        response.StatusCode = status;
        return response.WriteAsJsonAsync(new { code, message = "Synthetic lab response." });
    }
}

internal sealed record FaultCounter(string ProfileId, string Digest, int Remaining);

internal sealed class FaultControl(WorkerPaths paths, TimeProvider clock)
{
    private readonly object gate = new();
    private string? currentText;
    private string? currentId;
    private long start;
    private TimeSpan lifetime;

    internal (int Delay, bool Fail) Next()
    {
        lock (gate)
        {
            if (!File.Exists(paths.Fault)) return (0, false);
            var text = PrivateFiles.Read(paths.Fault, 4096);
            var profile = StrictJson.Read<FaultProfile>(text);
            var now = clock.GetUtcNow();
            profile.Validate(now);
            if (profile.ProfileId != currentId)
            {
                currentId = profile.ProfileId;
                currentText = text;
                start = clock.GetTimestamp();
                lifetime = profile.ExpiresUtc - now;
            }
            else if (text != currentText) throw new InvalidDataException("ChangedFaultState");
            if (now >= profile.ExpiresUtc || clock.GetElapsedTime(start) >= lifetime) return (0, false);
            PrivateFiles.CheckPath(paths.FaultCounter);
            var options = new FileStreamOptions { Mode = FileMode.OpenOrCreate, Access = FileAccess.ReadWrite, Share = FileShare.None };
            if (!OperatingSystem.IsWindows())
                options.UnixCreateMode = UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.GroupRead;
            var exists = File.Exists(paths.FaultCounter);
            using var stream = new FileStream(paths.FaultCounter, options);
            if (stream.Length > 4096 || exists && stream.Length == 0)
                throw new InvalidDataException("InvalidFaultCounter");
            var digest = Convert.ToHexString(SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(text)));
            var counter = new FaultCounter(profile.ProfileId, digest, profile.FailureCount);
            if (exists)
            {
                using var reader = new StreamReader(stream, leaveOpen: true);
                var saved = StrictJson.Read<FaultCounter>(reader.ReadToEnd());
                if (saved.ProfileId == profile.ProfileId)
                {
                    if (saved.Digest != digest || saved.Remaining < 0 || saved.Remaining > profile.FailureCount)
                        throw new InvalidDataException("InvalidFaultCounter");
                    counter = saved;
                }
            }
            var fail = counter.Remaining > 0;
            stream.Position = 0;
            stream.SetLength(0);
            JsonSerializer.Serialize(stream, counter with { Remaining = Math.Max(0, counter.Remaining - 1) }, StrictJson.Options);
            stream.Flush(true);
            return (profile.DelayMilliseconds, fail);
        }
    }
}

internal sealed record SyntheticOperation(string ApiId, string Route, string Method, int StatusCode,
    JsonElement Response, JsonElement Root, JsonElement Definition, JsonElement PathDefinition)
{
    internal async Task<bool> Accepts(HttpRequest request)
    {
        if (request.Query.Count > 16) return false;
        var parameters = new List<JsonElement>();
        foreach (var source in new[] { PathDefinition, Definition })
            if (source.TryGetProperty("parameters", out var list)) parameters.AddRange(list.EnumerateArray());
        foreach (var query in request.Query)
        {
            var parameter = parameters.FirstOrDefault(p => p.GetProperty("in").GetString() == "query" &&
                p.GetProperty("name").GetString() == query.Key);
            if (parameter.ValueKind == JsonValueKind.Undefined || query.Value.Count != 1 ||
                !SyntheticOperations.ScalarMatches(query.Value[0], parameter.GetProperty("schema"))) return false;
        }
        foreach (var parameter in parameters.Where(p => p.GetProperty("in").GetString() == "path"))
        {
            var name = parameter.GetProperty("name").GetString()!;
            if (!request.RouteValues.TryGetValue(name, out var value) ||
                !SyntheticOperations.ScalarMatches(value?.ToString(), parameter.GetProperty("schema"))) return false;
        }
        if (!Definition.TryGetProperty("requestBody", out var body))
            return request.ContentLength is null or 0 && !request.Headers.ContainsKey("Transfer-Encoding");
        if (request.ContentLength is > 16_384 || request.ContentType?.Split(';')[0].Trim() != "application/json") return false;
        try
        {
            using var buffer = new MemoryStream();
            var block = new byte[4096];
            int count;
            while ((count = await request.Body.ReadAsync(block, request.HttpContext.RequestAborted)) > 0)
            {
                if (buffer.Length + count > 16_384) return false;
                buffer.Write(block, 0, count);
            }
            using var document = StrictJson.Document(System.Text.Encoding.UTF8.GetString(buffer.ToArray()));
            return SyntheticOperations.Matches(document.RootElement,
                body.GetProperty("content").GetProperty("application/json").GetProperty("schema"), Root);
        }
        catch (JsonException) { return false; }
        catch (InvalidDataException) { return false; }
    }
}

internal static class SyntheticOperations
{
    internal static readonly string[] ApiIds = ["e-commerce", "manufacturing", "plm", "service-management", "supply-chain"];

    internal static IReadOnlyList<SyntheticOperation> Load(string directory)
    {
        var operations = new List<SyntheticOperation>();
        foreach (var api in ApiIds)
        {
            using var document = JsonDocument.Parse(File.ReadAllText(Path.Combine(directory, api + ".openapi.json")));
            var root = document.RootElement.Clone();
            foreach (var path in root.GetProperty("paths").EnumerateObject())
            foreach (var method in path.Value.EnumerateObject().Where(p => p.Name is "get" or "post" or "put" or "patch" or "delete"))
            {
                var success = method.Value.GetProperty("responses").EnumerateObject().First(p => p.Name.StartsWith('2'));
                var schema = Resolve(success.Value.GetProperty("content").GetProperty("application/json").GetProperty("schema"), root);
                var example = schema.GetProperty("example").Clone();
                if (!Matches(example, schema, root)) throw new InvalidDataException("InvalidSyntheticResponse");
                operations.Add(new(api, "/" + api + path.Name, method.Name.ToUpperInvariant(),
                    int.Parse(success.Name, CultureInfo.InvariantCulture), example, root, method.Value, path.Value));
            }
        }
        if (operations.Count != 16) throw new InvalidDataException("IncompleteSyntheticOperations");
        return operations;
    }

    private static JsonElement Resolve(JsonElement schema, JsonElement root)
    {
        if (!schema.TryGetProperty("$ref", out var reference)) return schema;
        var value = reference.GetString();
        const string prefix = "#/components/schemas/";
        if (value is null || !value.StartsWith(prefix, StringComparison.Ordinal) || value[prefix.Length..].Contains('/'))
            throw new InvalidDataException("UnsupportedSyntheticReference");
        return root.GetProperty("components").GetProperty("schemas").GetProperty(value[prefix.Length..]);
    }

    internal static bool Matches(JsonElement value, JsonElement schema, JsonElement root, int depth = 0)
    {
        if (depth > 16) return false;
        schema = Resolve(schema, root);
        if (schema.TryGetProperty("enum", out var choices) &&
            !choices.EnumerateArray().Any(choice => choice.GetRawText() == value.GetRawText())) return false;
        switch (schema.GetProperty("type").GetString())
        {
            case "object":
                if (value.ValueKind != JsonValueKind.Object) return false;
                if (schema.TryGetProperty("required", out var required) &&
                    required.EnumerateArray().Any(p => !value.TryGetProperty(p.GetString()!, out _))) return false;
                var properties = schema.GetProperty("properties");
                return value.EnumerateObject().All(p => properties.TryGetProperty(p.Name, out var nested) &&
                    Matches(p.Value, nested, root, depth + 1));
            case "array":
                return value.ValueKind == JsonValueKind.Array &&
                    (!schema.TryGetProperty("minItems", out var minItems) || value.GetArrayLength() >= minItems.GetInt32()) &&
                    (!schema.TryGetProperty("maxItems", out var maxItems) || value.GetArrayLength() <= maxItems.GetInt32()) &&
                    value.EnumerateArray().All(item => Matches(item, schema.GetProperty("items"), root, depth + 1));
            case "string":
                if (value.ValueKind != JsonValueKind.String) return false;
                var text = value.GetString()!;
                if (schema.TryGetProperty("minLength", out var minLength) && text.Length < minLength.GetInt32() ||
                    schema.TryGetProperty("maxLength", out var maxLength) && text.Length > maxLength.GetInt32()) return false;
                if (schema.TryGetProperty("format", out var format))
                    return format.GetString() switch
                    {
                        "date-time" => DateTimeOffset.TryParse(text, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out _),
                        "date" => DateOnly.TryParseExact(text, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out _),
                        _ => throw new InvalidDataException("UnsupportedSyntheticFormat")
                    };
                return !schema.TryGetProperty("pattern", out var pattern) ||
                    Regex.IsMatch(text, pattern.GetString()!, RegexOptions.CultureInvariant | RegexOptions.NonBacktracking);
            case "integer":
                return value.ValueKind == JsonValueKind.Number && value.TryGetInt64(out var number) &&
                    (!schema.TryGetProperty("minimum", out var min) || number >= min.GetInt64()) &&
                    (!schema.TryGetProperty("maximum", out var max) || number <= max.GetInt64());
            case "boolean": return value.ValueKind is JsonValueKind.True or JsonValueKind.False;
            default: throw new InvalidDataException("UnsupportedSyntheticType");
        }
    }

    internal static bool ScalarMatches(string? text, JsonElement schema)
    {
        if (text is null || text.Length > 2048) return false;
        if (schema.GetProperty("type").GetString() == "integer")
        {
            if (!long.TryParse(text, NumberStyles.None, CultureInfo.InvariantCulture, out var number)) return false;
            using var document = JsonDocument.Parse(number.ToString(CultureInfo.InvariantCulture));
            return Matches(document.RootElement, schema, schema);
        }
        using var scalar = JsonDocument.Parse(JsonSerializer.Serialize(text));
        return Matches(scalar.RootElement, schema, schema);
    }
}
