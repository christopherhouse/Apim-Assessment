using System.Globalization;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Security;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using LabWorker;
using Microsoft.AspNetCore.Hosting.Server;
using Microsoft.AspNetCore.Hosting.Server.Features;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Protocols;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;
using Microsoft.IdentityModel.Tokens;

internal static class WorkerTests
{
    private static int passed;
    private static int failed;
    private static readonly WorkerConfig Config = new("1.0", "11111111-1111-1111-1111-111111111111",
        "33333333-3333-3333-3333-333333333333", ["44444444-4444-4444-4444-444444444444"],
        "55555555-5555-5555-5555-555555555555", "https://backend.synthetic.invalid",
        "https://apim.synthetic.invalid", "https://gateway.synthetic.invalid");

    private static void Check(bool condition)
    {
        if (!condition) throw new InvalidOperationException("SyntheticAssertionFailed");
    }

    private static void Refuses(Action action)
    {
        try { action(); }
        catch (Exception exception) when (exception is InvalidDataException or JsonException or KeyNotFoundException or
            InvalidOperationException or FileNotFoundException)
        { return; }
        throw new InvalidOperationException("SyntheticInputAccepted");
    }

    private static async Task Case(string name, Func<Task> action)
    {
        try { await action(); passed++; }
        catch (Exception exception) { Console.Out.WriteLine($"FAIL:{name}:{exception.GetType().Name}"); failed++; }
    }

    private static Task Case(string name, Action action) => Case(name, () => { action(); return Task.CompletedTask; });

    private static void WritePrivate(string path, string text)
    {
        File.WriteAllText(path, text);
        if (!OperatingSystem.IsWindows())
            File.SetUnixFileMode(path, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.GroupRead);
    }

    private static HttpClient FakeClient(Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> send) =>
        new(new FakeHandler(send)) { Timeout = TimeSpan.FromSeconds(3) };

    private static HttpResponseMessage JsonResponse(int status, string body) =>
        new((HttpStatusCode)status) { Content = new StringContent(body, Encoding.UTF8, "application/json") };

    public static async Task<int> Main(string[] args)
    {
        if (args.Length != 1 || !Path.IsPathFullyQualified(args[0])) return 1;
        var root = Path.Combine(args[0], "synthetic-worker-runtime");
        Directory.CreateDirectory(root);
        Directory.CreateDirectory(Path.Combine(root, "runtime"));
        var paths = new WorkerPaths(Path.Combine(root, "config.json"), Path.Combine(root, "cert.pem"),
            Path.Combine(root, "key.pem"), root, Path.Combine(AppContext.BaseDirectory, "scenarios"));
        var configText = JsonSerializer.Serialize(Config, StrictJson.Options);
        WritePrivate(paths.Config, configText);

        await Case("closed-configuration", () => Check(WorkerConfig.Parse(configText).TenantId == Config.TenantId));
        foreach (var mutation in new Dictionary<string, string>
        {
            ["unknown-field"] = configText[..^1] + ",\"clientSecret\":\"SYNTHETIC_PRIVATE_CANARY\"}",
            ["duplicate-case"] = configText[..^1] + ",\"SchemaVersion\":\"1.0\"}",
            ["version"] = configText.Replace("\"1.0\"", "\"2.0\"", StringComparison.Ordinal),
            ["empty-callers"] = configText.Replace("[\"44444444-4444-4444-4444-444444444444\"]", "[]", StringComparison.Ordinal),
            ["delegated-authority"] = configText.Replace(Config.TenantId, "common", StringComparison.Ordinal),
            ["audience-confusion"] = configText.Replace(Config.FrontendResourceClientId, Config.BackendAudienceClientId, StringComparison.Ordinal),
            ["http-origin"] = configText.Replace(Config.BackendOrigin, "http://backend.synthetic.invalid", StringComparison.Ordinal),
            ["origin-query"] = configText.Replace(Config.BackendOrigin, Config.BackendOrigin + "?token=canary", StringComparison.Ordinal),
            ["origin-port"] = configText.Replace(Config.BackendOrigin, Config.BackendOrigin + ":8443", StringComparison.Ordinal)
        })
            await Case("reject-config-" + mutation.Key, () => Refuses(() => WorkerConfig.Parse(mutation.Value)));

        await Case("job-version-and-shape", () =>
        {
            Check(JobRequest.Parse("{\"schemaVersion\":\"1.0\",\"kind\":\"readiness\"}").Kind == "readiness");
            Refuses(() => JobRequest.Parse("{\"schemaVersion\":\"1.0\",\"kind\":\"readiness\",\"url\":\"https://canary.invalid\"}"));
            Refuses(() => JobRequest.Parse("{\"schemaVersion\":\"1.0\",\"kind\":\"readiness\",\"Kind\":\"traffic\"}"));
            Refuses(() => JobRequest.Parse("{\"schemaVersion\":\"2.0\",\"kind\":\"readiness\"}"));
            Refuses(() => JobRequest.Parse("{\"schemaVersion\":\"1.0\",\"kind\":\"shell\"}"));
        });
        await Case("traffic-measured-bounds", () =>
        {
            foreach (var count in new[] { 0, 21 })
                Refuses(() => JobRequest.Parse($"{{\"schemaVersion\":\"1.0\",\"kind\":\"traffic\",\"profile\":\"supply-chain\",\"requestCount\":{count},\"intervalMilliseconds\":250}}"));
            foreach (var interval in new[] { 249, 2001 })
                Refuses(() => JobRequest.Parse($"{{\"schemaVersion\":\"1.0\",\"kind\":\"traffic\",\"profile\":\"supply-chain\",\"requestCount\":1,\"intervalMilliseconds\":{interval}}}"));
            Refuses(() => JobRequest.Parse("{\"schemaVersion\":\"1.0\",\"kind\":\"traffic\",\"profile\":\"manufacturing\",\"requestCount\":1,\"intervalMilliseconds\":250}"));
        });
        await Case("fault-measured-bounds", () =>
        {
            foreach (var bad in new[] { (121, 0, 1), (0, 0, 1), (1, 1001, 1), (1, -1, 1), (1, 0, 11), (1, 0, 0) })
                Refuses(() => JobRequest.Parse($"{{\"schemaVersion\":\"1.0\",\"kind\":\"fault\",\"durationSeconds\":{bad.Item1},\"delayMilliseconds\":{bad.Item2},\"failureCount\":{bad.Item3}}}"));
        });
        await Case("private-read-refuses-relative-and-oversize", () =>
        {
            Refuses(() => PrivateFiles.Read("relative.json"));
            WritePrivate(Path.Combine(root, "large.json"), new string('x', 4097));
            Refuses(() => PrivateFiles.Read(Path.Combine(root, "large.json"), 4096));
        });
        await Case("cli-all-streams-fixed", async () =>
        {
            var output = new StringWriter(CultureInfo.InvariantCulture);
            var error = new StringWriter(CultureInfo.InvariantCulture);
            var previousOut = Console.Out;
            var previousError = Console.Error;
            try
            {
                Console.SetOut(output);
                Console.SetError(error);
                Check(await LabWorker.Program.Main(["SYNTHETIC_PRIVATE_CANARY"]) == 1);
            }
            finally { Console.SetOut(previousOut); Console.SetError(previousError); }
            Check(output.ToString().Trim() == "LAB_WORKER_FAILED" && error.ToString() == "");
        });

        using var signing = RSA.Create(2048);
        using var caKey = RSA.Create(2048);
        var caRequest = new CertificateRequest("CN=Synthetic Lab CA", caKey, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        caRequest.CertificateExtensions.Add(new X509BasicConstraintsExtension(true, false, 0, true));
        caRequest.CertificateExtensions.Add(new X509KeyUsageExtension(X509KeyUsageFlags.KeyCertSign, true));
        using var ca = caRequest.CreateSelfSigned(DateTimeOffset.UtcNow.AddDays(-1), DateTimeOffset.UtcNow.AddDays(2));
        using var leafKey = RSA.Create(2048);
        var leafRequest = new CertificateRequest("CN=backend.synthetic.invalid", leafKey, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        leafRequest.CertificateExtensions.Add(new X509BasicConstraintsExtension(false, false, 0, true));
        leafRequest.CertificateExtensions.Add(new X509KeyUsageExtension(X509KeyUsageFlags.DigitalSignature | X509KeyUsageFlags.KeyEncipherment, true));
        leafRequest.CertificateExtensions.Add(new X509EnhancedKeyUsageExtension(new OidCollection { new("1.3.6.1.5.5.7.3.1") }, true));
        var san = new SubjectAlternativeNameBuilder();
        san.AddDnsName("backend.synthetic.invalid");
        san.AddIpAddress(IPAddress.Loopback);
        leafRequest.CertificateExtensions.Add(san.Build());
        using var publicLeaf = leafRequest.Create(ca, DateTimeOffset.UtcNow.AddMinutes(-5),
            DateTimeOffset.UtcNow.AddDays(1), RandomNumberGenerator.GetBytes(16));
        using var leaf = publicLeaf.CopyWithPrivateKey(leafKey);
        WritePrivate(paths.Certificate, leaf.ExportCertificatePem() + "\n" + ca.ExportCertificatePem());
        WritePrivate(paths.Key, leafKey.ExportPkcs8PrivateKeyPem());
        var key = new RsaSecurityKey(signing) { KeyId = "synthetic-signing-key" };
        var discovery = new OpenIdConnectConfiguration { Issuer = Config.Issuer };
        discovery.SigningKeys.Add(key);
        var clock = new ManualClock();
        await using var app = Backend.Build(Config, paths, IPAddress.Loopback, 0,
            new StaticConfigurationManager<OpenIdConnectConfiguration>(discovery), clock);
        await app.StartAsync();
        var origin = app.Services.GetRequiredService<IServer>().Features.Get<IServerAddressesFeature>()!.Addresses.Single();
        using var client = new HttpClient(new HttpClientHandler
        {
            AllowAutoRedirect = false,
            SslProtocols = System.Security.Authentication.SslProtocols.Tls12,
            ServerCertificateCustomValidationCallback = (_, certificate, _, errors) =>
            {
                if (certificate is null || (errors & SslPolicyErrors.RemoteCertificateNameMismatch) != 0) return false;
                using var trustedChain = new X509Chain();
                trustedChain.ChainPolicy.TrustMode = X509ChainTrustMode.CustomRootTrust;
                trustedChain.ChainPolicy.CustomTrustStore.Add(ca);
                trustedChain.ChainPolicy.RevocationMode = X509RevocationMode.NoCheck;
                return trustedChain.Build(certificate);
            }
        }) { BaseAddress = new Uri(origin), Timeout = TimeSpan.FromSeconds(5) };

        string Token(Action<SecurityTokenDescriptor>? mutate = null)
        {
            var descriptor = new SecurityTokenDescriptor
            {
                Issuer = Config.Issuer, Audience = Config.BackendAudienceClientId,
                NotBefore = DateTime.UtcNow.AddMinutes(-10), IssuedAt = DateTime.UtcNow.AddMinutes(-10),
                Expires = DateTime.UtcNow.AddMinutes(5),
                Claims = new Dictionary<string, object>
                {
                    ["tid"] = Config.TenantId, ["ver"] = "2.0", ["azp"] = Config.BackendCallerClientIds[0],
                    ["roles"] = new[] { WorkerConfig.BackendRole }
                },
                SigningCredentials = new SigningCredentials(key, SecurityAlgorithms.RsaSha256)
            };
            mutate?.Invoke(descriptor);
            return new JsonWebTokenHandler().CreateToken(descriptor);
        }

        async Task<HttpResponseMessage> Send(string path, string? token = null, string method = "GET", string? body = null)
        {
            using var request = new HttpRequestMessage(new HttpMethod(method), path);
            if (token is not null) request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
            if (body is not null) request.Content = new StringContent(body, Encoding.UTF8, "application/json");
            return await client.SendAsync(request);
        }

        var validToken = Token();
        await Case("actual-tls12-health", async () =>
        {
            using var response = await Send("/healthz");
            Check(response.StatusCode == HttpStatusCode.OK);
            Check((await response.Content.ReadAsStringAsync()).Contains("LAB_WORKER_BACKEND_READY", StringComparison.Ordinal));
        });
        await Case("tls-untrusted-root-is-not-ready", async () =>
        {
            using var strict = Jobs.CreateClient();
            var fixture = Config with { BackendOrigin = origin };
            var result = await new Jobs(fixture, paths, strict, TimeProvider.System).Run(new("readiness"));
            Check(result.State == "NotReady");
        });
        await Case("tls-wrong-host-refused-before-listen", () =>
            Refuses(() => Backend.Build(Config with { BackendOrigin = "https://wrong.synthetic.invalid" }, paths)));
        await Case("tls-missing-expired-or-future-certificate-refused", () =>
        {
            Refuses(() => Backend.Build(Config, paths with { Certificate = Path.Combine(root, "missing-cert.pem") }));
            foreach (var offset in new[] { TimeSpan.FromDays(2), TimeSpan.FromHours(-1) })
            {
                var certificateClock = new ManualClock();
                certificateClock.Advance(offset);
                Refuses(() => Backend.Build(Config, paths, clock: certificateClock));
            }
        });
        await Case("missing-bearer-denied", async () =>
        {
            using var response = await Send("/supply-chain/inventory");
            Check(response.StatusCode == HttpStatusCode.Unauthorized);
        });
        foreach (var test in new Dictionary<string, (Action<SecurityTokenDescriptor> Mutate, int Status)>
        {
            ["issuer"] = (d => d.Issuer = "https://issuer.invalid", 401),
            ["audience"] = (d => d.Audience = Config.FrontendResourceClientId, 401),
            ["expired"] = (d => d.Expires = DateTime.UtcNow.AddMinutes(-2), 401),
            ["not-yet-valid"] = (d => { d.NotBefore = DateTime.UtcNow.AddMinutes(2); d.Expires = DateTime.UtcNow.AddMinutes(5); }, 401),
            ["unsigned"] = (d => d.SigningCredentials = null, 401),
            ["tenant"] = (d => d.Claims["tid"] = "66666666-6666-6666-6666-666666666666", 403),
            ["version"] = (d => d.Claims["ver"] = "1.0", 403),
            ["role"] = (d => d.Claims["roles"] = new[] { "Lab.Other.Invoke" }, 403),
            ["missing-role"] = (d => d.Claims.Remove("roles"), 403),
            ["caller"] = (d => d.Claims["azp"] = "77777777-7777-7777-7777-777777777777", 403),
            ["missing-caller"] = (d => d.Claims.Remove("azp"), 403),
            ["delegated-token"] = (d => d.Claims["scp"] = "access_as_user", 403)
        })
        {
            await Case("reject-token-" + test.Key, async () =>
            {
                using var response = await Send("/supply-chain/inventory", Token(test.Value.Mutate));
                Check((int)response.StatusCode == test.Value.Status);
            });
        }
        await Case("reject-signature-and-algorithm-substitution", async () =>
        {
            using var other = RSA.Create(2048);
            foreach (var credentials in new[]
            {
                new SigningCredentials(new RsaSecurityKey(other) { KeyId = key.KeyId }, SecurityAlgorithms.RsaSha256),
                new SigningCredentials(new SymmetricSecurityKey(RandomNumberGenerator.GetBytes(32)), SecurityAlgorithms.HmacSha256)
            })
            {
                using var response = await Send("/supply-chain/inventory", Token(d => d.SigningCredentials = credentials));
                Check(response.StatusCode == HttpStatusCode.Unauthorized);
            }
        });

        foreach (var operation in SyntheticOperations.Load(paths.Scenarios))
        {
            await Case("operation-" + operation.ApiId + "-" + operation.Definition.GetProperty("operationId").GetString(), async () =>
            {
                string? body = null;
                if (operation.Definition.TryGetProperty("requestBody", out var request))
                {
                    var schema = request.GetProperty("content").GetProperty("application/json").GetProperty("schema");
                    if (schema.TryGetProperty("$ref", out var reference))
                        schema = operation.Root.GetProperty("components").GetProperty("schemas").GetProperty(reference.GetString()!.Split('/')[^1]);
                    body = schema.GetProperty("example").GetRawText();
                }
                var route = operation.Route;
                if (operation.PathDefinition.TryGetProperty("parameters", out var parameters))
                    foreach (var parameter in parameters.EnumerateArray())
                    {
                        var example = parameter.GetProperty("example");
                        var value = example.ValueKind == JsonValueKind.String ? example.GetString()! : example.GetRawText();
                        route = route.Replace("{" + parameter.GetProperty("name").GetString() + "}", Uri.EscapeDataString(value), StringComparison.Ordinal);
                    }
                using var response = await Send(route, validToken, operation.Method, body);
                Check((int)response.StatusCode == operation.StatusCode);
                using var result = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
                Check(JsonElement.DeepEquals(result.RootElement, operation.Response));
            });
        }
        await Case("deny-never-forwards-and-does-not-echo", async () =>
        {
            foreach (var route in new[] { "/deny/plm", "/not-a-lab-api?SYNTHETIC_PRIVATE_CANARY=value", "/fault" })
            {
                using var response = await Send(route);
                Check(response.StatusCode == HttpStatusCode.Forbidden);
                Check(!(await response.Content.ReadAsStringAsync()).Contains("SYNTHETIC_PRIVATE_CANARY", StringComparison.Ordinal));
            }
        });
        await Case("invalid-query-and-private-fault-toggle-denied", async () =>
        {
            foreach (var route in new[] { "/supply-chain/inventory?limit=0", "/service-management/tickets/TKT-1001?fault=true" })
            {
                using var response = await Send(route, validToken);
                Check(response.StatusCode == HttpStatusCode.BadRequest);
            }
            Check(!File.Exists(paths.Fault));
        });
        await Case("invalid-body-and-oversize-do-not-echo", async () =>
        {
            foreach (var body in new[]
            {
                "{\"warehouseCode\":\"WH-01\",\"destinationCode\":\"STORE-02\",\"items\":[{\"sku\":\"SKU-100\",\"quantity\":\"SYNTHETIC_PRIVATE_CANARY\"}]}",
                "{\"warehouseCode\":\"WH-01\",\"WarehouseCode\":\"WH-02\",\"destinationCode\":\"STORE-02\",\"items\":[]}",
                "{\"canary\":\"" + new string('x', 20_000) + "\"}"
            })
            {
                using var response = await Send("/supply-chain/shipments", validToken, "POST", body);
                Check((int)response.StatusCode is 400 or 413);
                Check(!(await response.Content.ReadAsStringAsync()).Contains("SYNTHETIC_PRIVATE_CANARY", StringComparison.Ordinal));
            }
        });

        using var noNetwork = FakeClient((_, _) => throw new InvalidOperationException("UnexpectedNetwork"));
        var jobs = new Jobs(Config, paths, noNetwork, clock);
        await Case("private-fault-is-scoped-and-request-bounded", async () =>
        {
            Check((await jobs.Run(new("fault", DurationSeconds: 30, FailureCount: 2))).State == "Ready");
            using (var otherApi = await Send("/supply-chain/inventory", validToken)) Check((int)otherApi.StatusCode == 200);
            for (var index = 0; index < 3; index++)
            {
                using var response = await Send("/service-management/tickets/TKT-1001", validToken);
                Check((int)response.StatusCode == (index < 2 ? 503 : 200));
            }
            Check(!new FaultControl(paths, clock).Next().Fail);
            Check((await jobs.Run(new("clearFault"))).State == "Ready");
        });
        await Case("fault-expiry-and-monotonic-deadline", async () =>
        {
            Check((await jobs.Run(new("fault", DurationSeconds: 120, FailureCount: 10))).State == "Ready");
            var control = new FaultControl(paths, clock);
            Check(control.Next().Fail);
            clock.Advance(TimeSpan.FromSeconds(121), advanceUtc: false);
            Check(!control.Next().Fail);
            clock.Advance(TimeSpan.FromSeconds(121));
            Check(!new FaultControl(paths, clock).Next().Fail);
            Check((await jobs.Run(new("clearFault"))).State == "Ready");
        });
        await Case("tampered-persistent-fault-counter-refused", async () =>
        {
            Check((await jobs.Run(new("fault", DurationSeconds: 30, FailureCount: 2))).State == "Ready");
            Check(new FaultControl(paths, clock).Next().Fail);
            var saved = StrictJson.Read<FaultCounter>(File.ReadAllText(paths.FaultCounter));
            foreach (var changed in new[] { saved with { Remaining = 3 }, saved with { Remaining = -1 },
                saved with { Digest = "SYNTHETIC_PRIVATE_CANARY" } })
            {
                WritePrivate(paths.FaultCounter, JsonSerializer.Serialize(changed, StrictJson.Options));
                Refuses(() => new FaultControl(paths, clock).Next());
            }
            Check((await jobs.Run(new("clearFault"))).State == "Ready");
        });
        await Case("malformed-fault-state-does-not-pass", async () =>
        {
            WritePrivate(paths.Fault, "{\"SYNTHETIC_PRIVATE_CANARY\":true}");
            using var response = await Send("/service-management/tickets/TKT-1001", validToken);
            Check((int)response.StatusCode == 503);
            Check(!(await response.Content.ReadAsStringAsync()).Contains("SYNTHETIC_PRIVATE_CANARY", StringComparison.Ordinal));
            Check((await jobs.Run(new("clearFault"))).State == "Ready");
        });
        await Case("private-job-serialization", async () =>
        {
            using var held = new FileStream(paths.Lock, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            Check((await jobs.Run(new("readiness"))).State == "Failed");
        });
        await Case("invalid-direct-job-cannot-pass-zero-calls", async () =>
            Check((await jobs.Run(new("traffic", "supply-chain", 0, 250))).State == "Failed"));
        await Case("cancelled-job-does-not-write-fault", async () =>
        {
            using var cancelled = new CancellationTokenSource();
            cancelled.Cancel();
            Check((await jobs.Run(new("fault", DurationSeconds: 1, FailureCount: 1), cancelled.Token)).State == "NotReady");
            Check(!File.Exists(paths.Fault));
        });
        await Case("readiness-requires-exact-safe-body", async () =>
        {
            foreach (var body in new[] { "{}", "{\"state\":\"Ready\",\"code\":\"wrong\"}", new string('x', 1025) })
            {
                using var fake = FakeClient((_, _) => Task.FromResult(JsonResponse(200, body)));
                Check((await new Jobs(Config, paths, fake, TimeProvider.System).Run(new("readiness"))).State != "Ready");
            }
            using var ready = FakeClient((_, _) => Task.FromResult(JsonResponse(200,
                "{\"state\":\"Ready\",\"code\":\"LAB_WORKER_BACKEND_READY\"}")));
            Check((await new Jobs(Config, paths, ready, TimeProvider.System).Run(new("readiness"))).State == "Ready");
        });
        await Case("traffic-calls-interval-identity-and-profile", async () =>
        {
            var requests = new List<(Uri Uri, string? Token, long Tick)>();
            using var fake = FakeClient((request, _) =>
            {
                if (request.RequestUri!.Host == "169.254.169.254")
                {
                    Check(request.Headers.GetValues("Metadata").Single() == "true");
                    Check(request.RequestUri.Query.Contains(Uri.EscapeDataString("api://" + Config.FrontendResourceClientId), StringComparison.Ordinal));
                    return Task.FromResult(JsonResponse(200, JsonSerializer.Serialize(new
                    {
                        access_token = "synthetic.payload.signature", token_type = "Bearer",
                        expires_on = DateTimeOffset.UtcNow.AddHours(1).ToUnixTimeSeconds().ToString(CultureInfo.InvariantCulture)
                    })));
                }
                requests.Add((request.RequestUri, request.Headers.Authorization?.Parameter, Environment.TickCount64));
                return Task.FromResult(JsonResponse(200, "{}"));
            });
            Check((await new Jobs(Config, paths, fake, TimeProvider.System)
                .Run(new("traffic", "plm-private", 3, 250))).State == "Ready");
            Check(requests.Count == 3 && requests.All(r => r.Uri.AbsoluteUri == Config.ApimOrigin + "/plm/parts/PART-1001/revisions/A"));
            Check(requests.All(r => r.Token == "synthetic.payload.signature"));
            Check(requests[2].Tick - requests[0].Tick >= 450);
        });
        await Case("traffic-maximum-is-twenty", async () =>
        {
            var calls = 0;
            using var fake = FakeClient((_, _) =>
            {
                calls++;
                return Task.FromResult(JsonResponse(403, "{}"));
            });
            Check((await new Jobs(Config, paths, fake, TimeProvider.System)
                .Run(new("traffic", "unmatched-denied", 20, 250))).State == "Ready");
            Check(calls == 20);
        });
        await Case("whole-job-sixty-second-budget", async () =>
        {
            var budgetClock = new ManualClock();
            using var fake = FakeClient((_, cancellation) =>
            {
                budgetClock.Advance(TimeSpan.FromSeconds(61));
                cancellation.ThrowIfCancellationRequested();
                return Task.FromResult(JsonResponse(403, "{}"));
            });
            Check((await new Jobs(Config, paths, fake, budgetClock)
                .Run(new("traffic", "unmatched-denied", 20, 250))).State == "NotReady");
        });
        await Case("redirect-mismatch-and-missing-role-never-pass", async () =>
        {
            foreach (var status in new[] { 301, 302, 401, 403, 500 })
            {
                var count = 0;
                using var fake = FakeClient((_, _) =>
                {
                    count++;
                    var response = JsonResponse(status, "{}");
                    response.Headers.Location = new Uri("https://SYNTHETIC_PRIVATE_CANARY.invalid");
                    return Task.FromResult(response);
                });
                var result = await new Jobs(Config, paths, fake, TimeProvider.System).Run(new("readiness"));
                Check(result.State == "NotReady" && count == 1);
            }
        });
        await Case("metadata-failure-does-not-send-traffic", async () =>
        {
            var count = 0;
            using var fake = FakeClient((request, _) =>
            {
                count++;
                Check(request.RequestUri!.Host == "169.254.169.254");
                return Task.FromResult(JsonResponse(403, "{}"));
            });
            Check((await new Jobs(Config, paths, fake, TimeProvider.System)
                .Run(new("traffic", "supply-chain", 1, 250))).State == "NotReady");
            Check(count == 1);
        });
        await Case("metadata-oversize-is-not-ready", async () =>
        {
            using var fake = FakeClient((_, _) => Task.FromResult(JsonResponse(200, new string('x', 32_769))));
            Check((await new Jobs(Config, paths, fake, TimeProvider.System)
                .Run(new("traffic", "supply-chain", 1, 250))).State == "NotReady");
        });
        await app.StopAsync();
        Console.Out.WriteLine(failed == 0 ? $"LAB_WORKER_TESTS_PASSED:{passed}" : $"LAB_WORKER_TESTS_FAILED:{failed}");
        return failed == 0 ? 0 : 1;
    }
}

internal sealed class FakeHandler(Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> send) : HttpMessageHandler
{
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) =>
        send(request, cancellationToken);
}

internal sealed class ManualClock : TimeProvider
{
    private DateTimeOffset utc = DateTimeOffset.UtcNow;
    private long ticks;
    private readonly List<ManualTimer> timers = [];
    public override DateTimeOffset GetUtcNow() => utc;
    public override long GetTimestamp() => ticks;
    public override long TimestampFrequency => TimeSpan.TicksPerSecond;
    public override ITimer CreateTimer(TimerCallback callback, object? state, TimeSpan dueTime, TimeSpan period)
    {
        var timer = new ManualTimer(this, callback, state, dueTime);
        timers.Add(timer);
        return timer;
    }
    internal void Advance(TimeSpan duration, bool advanceUtc = true)
    {
        ticks += duration.Ticks;
        if (advanceUtc) utc += duration;
        foreach (var timer in timers.ToArray()) timer.Fire(ticks);
    }
    private sealed class ManualTimer(ManualClock clock, TimerCallback callback, object? state, TimeSpan dueTime) : ITimer
    {
        private long due = clock.ticks + dueTime.Ticks;
        private bool disposed;
        public bool Change(TimeSpan dueTime, TimeSpan period) { due = clock.ticks + dueTime.Ticks; return !disposed; }
        public void Dispose() => disposed = true;
        public ValueTask DisposeAsync() { Dispose(); return ValueTask.CompletedTask; }
        internal void Fire(long now)
        {
            if (disposed || now < due) return;
            disposed = true;
            callback(state);
        }
    }
}
