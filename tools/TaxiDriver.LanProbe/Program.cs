using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Text;

namespace TaxiDriver.LanProbe;

internal static class Program
{
    private const string TargetPath = "/ui/modules/apps/TaxiDriverHUD/external/index.html";

    public static async Task<int> Main(string[] args)
    {
        Console.OutputEncoding = Encoding.UTF8;
        return await RunSelfTestAsync();
    }

    private static async Task<int> RunSelfTestAsync()
    {
        var lanAddress = FindLanAddress();
        var upstream = new TcpListener(IPAddress.Loopback, 0);
        upstream.Start();
        var upstreamPort = ((IPEndPoint)upstream.LocalEndpoint).Port;
        var proxyPort = FindFreePort(lanAddress);
        using var bridge = new LanBridge(lanAddress, proxyPort, IPAddress.Loopback, upstreamPort);
        bridge.Start();
        using var cancellation = new CancellationTokenSource(TimeSpan.FromSeconds(10));
        var bridgeTask = bridge.RunAsync(cancellation.Token);
        var upstreamTask = Task.Run(async () =>
        {
            using (var httpClient = await upstream.AcceptTcpClientAsync(cancellation.Token))
            {
                using var stream = httpClient.GetStream();
                _ = await ReadHttpHeaderAsync(stream, cancellation.Token);
                const string body = "TaxiDriver subnet probe OK";
                var response = Encoding.ASCII.GetBytes(
                    $"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: {body.Length}\r\nConnection: close\r\n\r\n{body}");
                await stream.WriteAsync(response, cancellation.Token);
            }
            using (var socketClient = await upstream.AcceptTcpClientAsync(cancellation.Token))
            {
                using var stream = socketClient.GetStream();
                var request = Encoding.ASCII.GetString(await ReadHttpHeaderAsync(stream, cancellation.Token));
                if (!request.Contains("Upgrade: websocket", StringComparison.OrdinalIgnoreCase))
                    throw new InvalidOperationException("The WebSocket upgrade did not reach the loopback server.");
                var response = Encoding.ASCII.GetBytes(
                    "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: test\r\n\r\n");
                await stream.WriteAsync(response, cancellation.Token);
                var payload = new byte[4];
                await stream.ReadExactlyAsync(payload, cancellation.Token);
                if (Encoding.ASCII.GetString(payload) != "PING")
                    throw new InvalidOperationException("Unexpected WebSocket tunnel payload.");
                await stream.WriteAsync("PONG"u8.ToArray(), cancellation.Token);
            }
        }, cancellation.Token);

        try
        {
            using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(5) };
            var body = await http.GetStringAsync($"http://{lanAddress}:{proxyPort}/subnet-test", cancellation.Token);
            if (body != "TaxiDriver subnet probe OK") throw new InvalidOperationException("Unexpected response body.");
            using var socket = new TcpClient();
            await socket.ConnectAsync(lanAddress, proxyPort, cancellation.Token);
            using var stream = socket.GetStream();
            var upgrade = Encoding.ASCII.GetBytes(
                $"GET / HTTP/1.1\r\nHost: {lanAddress}:{proxyPort}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGVzdA==\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Protocol: bng-ext-app-v1\r\n\r\n");
            await stream.WriteAsync(upgrade, cancellation.Token);
            var responseHeader = Encoding.ASCII.GetString(await ReadHttpHeaderAsync(stream, cancellation.Token));
            if (!responseHeader.Contains("101 Switching Protocols", StringComparison.Ordinal))
                throw new InvalidOperationException("WebSocket upgrade failed through the subnet bridge.");
            await stream.WriteAsync("PING"u8.ToArray(), cancellation.Token);
            var reply = new byte[4];
            await stream.ReadExactlyAsync(reply, cancellation.Token);
            if (Encoding.ASCII.GetString(reply) != "PONG")
                throw new InvalidOperationException("WebSocket return traffic failed through the subnet bridge.");
            await upstreamTask;
            Console.WriteLine($"PASS: HTTP reached the bridge through subnet address {lanAddress}:{proxyPort}.");
            Console.WriteLine("PASS: the loopback-only response travelled back through the LAN bridge.");
            Console.WriteLine("PASS: WebSocket Upgrade and bidirectional traffic crossed the subnet bridge.");
            return 0;
        }
        catch (Exception error)
        {
            Console.Error.WriteLine($"FAIL: {error.Message}");
            return 1;
        }
        finally
        {
            cancellation.Cancel();
            upstream.Stop();
            try { await bridgeTask; } catch (OperationCanceledException) { }
        }
    }

    private static IPAddress FindLanAddress()
    {
        var candidates = NetworkInterface.GetAllNetworkInterfaces()
            .Where(adapter => adapter.OperationalStatus == OperationalStatus.Up &&
                              adapter.NetworkInterfaceType != NetworkInterfaceType.Loopback)
            .SelectMany(adapter => adapter.GetIPProperties().UnicastAddresses)
            .Select(entry => entry.Address)
            .Where(address => address.AddressFamily == AddressFamily.InterNetwork &&
                              !IPAddress.IsLoopback(address) && !address.ToString().StartsWith("169.254."))
            .OrderByDescending(AddressScore)
            .ToArray();
        return candidates.FirstOrDefault() ?? throw new InvalidOperationException("No active IPv4 LAN address was found.");
    }

    private static int AddressScore(IPAddress address)
    {
        var value = address.ToString();
        if (value.StartsWith("192.168.")) return 30;
        if (value.StartsWith("10.")) return 20;
        var bytes = address.GetAddressBytes();
        return bytes[0] == 172 && bytes[1] is >= 16 and <= 31 ? 10 : 0;
    }

    private static int FindFreePort(IPAddress address)
    {
        var listener = new TcpListener(address, 0);
        listener.Start();
        var port = ((IPEndPoint)listener.LocalEndpoint).Port;
        listener.Stop();
        return port;
    }

    private static async Task<byte[]> ReadHttpHeaderAsync(NetworkStream stream, CancellationToken cancellationToken)
    {
        using var memory = new MemoryStream();
        var one = new byte[1];
        while (memory.Length < 64 * 1024)
        {
            if (await stream.ReadAsync(one, cancellationToken) == 0) break;
            memory.WriteByte(one[0]);
            if (memory.Length >= 4)
            {
                var value = memory.GetBuffer();
                var end = (int)memory.Length;
                if (value[end - 4] == 13 && value[end - 3] == 10 &&
                    value[end - 2] == 13 && value[end - 1] == 10) return memory.ToArray();
            }
        }
        throw new IOException("HTTP header was incomplete.");
    }

}

internal sealed class LanBridge : IDisposable
{
    private const int MaximumHeaderBytes = 64 * 1024;
    private readonly IPAddress listenAddress;
    private readonly int listenPort;
    private readonly IPAddress upstreamAddress;
    private readonly int upstreamPort;
    private readonly TcpListener listener;
    private readonly CancellationTokenSource lifetime = new();

    public LanBridge(IPAddress listenAddress, int listenPort, IPAddress upstreamAddress, int upstreamPort)
    {
        this.listenAddress = listenAddress;
        this.listenPort = listenPort;
        this.upstreamAddress = upstreamAddress;
        this.upstreamPort = upstreamPort;
        listener = new TcpListener(listenAddress, listenPort);
    }

    public void Start() => listener.Start(128);

    public async Task RunAsync(CancellationToken cancellationToken)
    {
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, lifetime.Token);
        while (!linked.IsCancellationRequested)
        {
            var client = await listener.AcceptTcpClientAsync(linked.Token);
            _ = HandleClientAsync(client, linked.Token);
        }
    }

    private async Task HandleClientAsync(TcpClient client, CancellationToken cancellationToken)
    {
        using (client)
        {
            client.NoDelay = true;
            var clientStream = client.GetStream();
            byte[] header;
            try { header = await ReadHeaderAsync(clientStream, cancellationToken); }
            catch { return; }
            var requestLine = Encoding.ASCII.GetString(header, 0, Math.Min(header.Length, 4096))
                .Split("\r\n", 2, StringSplitOptions.None)[0];
            if (requestLine.StartsWith("GET /__taxidriver_probe", StringComparison.Ordinal))
            {
                await WriteDiagnosticsAsync(clientStream, requestLine, cancellationToken);
                return;
            }

            using var upstream = new TcpClient { NoDelay = true };
            try { await upstream.ConnectAsync(upstreamAddress, upstreamPort, cancellationToken); }
            catch
            {
                await WriteResponseAsync(clientStream, "502 Bad Gateway",
                    "BeamNG UI App is not available on 127.0.0.1.", cancellationToken);
                return;
            }
            var upstreamStream = upstream.GetStream();
            await upstreamStream.WriteAsync(header, cancellationToken);
            var upstreamCopy = upstreamStream.CopyToAsync(clientStream, cancellationToken);
            var clientCopy = clientStream.CopyToAsync(upstreamStream, cancellationToken);
            await Task.WhenAny(upstreamCopy, clientCopy);
        }
    }

    private async Task WriteDiagnosticsAsync(NetworkStream stream, string requestLine, CancellationToken cancellationToken)
    {
        var token = "";
        var target = requestLine.Split(' ').ElementAtOrDefault(1) ?? "";
        if (Uri.TryCreate("http://probe" + target, UriKind.Absolute, out var uri))
        {
            token = uri.Query.TrimStart('?').Split('&')
                .Select(part => part.Split('=', 2))
                .FirstOrDefault(part => part.Length == 2 && part[0] == "token")?[1] ?? "";
        }
        var upstreamAvailable = false;
        try
        {
            using var probe = new TcpClient();
            await probe.ConnectAsync(upstreamAddress, upstreamPort, cancellationToken);
            upstreamAvailable = true;
        }
        catch { }
        var appUrl = $"http://{listenAddress}:{listenPort}{ProgramTargetPath()}" +
                     (string.IsNullOrWhiteSpace(token) ? "" : $"?token={Uri.EscapeDataString(token)}");
        var statusColor = upstreamAvailable ? "#59e391" : "#ff6c76";
        var statusText = upstreamAvailable ? "CONNECTED" : "FAILED";
        var action = upstreamAvailable
            ? $"<a href=\"{WebUtility.HtmlEncode(appUrl)}\">Open TaxiDriver</a>"
            : "<p>Enable Connected phone inside TaxiDriver first.</p>";
        var tokenHint = string.IsNullOrWhiteSpace(token)
            ? "<p>Append <code>?token=...</code> to carry the session token into TaxiDriver.</p>"
            : "";
        var html = $$"""
            <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
            <title>TaxiDriver LAN Probe</title><style>
            body{margin:0;background:#090c11;color:#f5f7fa;font:16px system-ui;display:grid;min-height:100vh;place-items:center}
            main{width:min(520px,calc(100% - 32px));background:#151a21;border:1px solid #343b46;border-radius:22px;padding:24px;box-sizing:border-box}
            h1{margin:0 0 8px;color:#ffd21c}.row{margin:14px 0;padding:14px;background:#0d1117;border-radius:12px}
            b{color:{{statusColor}}}a{display:block;margin-top:18px;padding:16px;text-align:center;background:#ffd21c;color:#15130a;border-radius:12px;font-weight:800;text-decoration:none}
            code{overflow-wrap:anywhere;color:#aeb8c5}</style></head><body><main><h1>TaxiDriver LAN Probe</h1>
            <p>This page was loaded through the laptop's subnet address.</p>
            <div class="row">Phone -&gt; LAN bridge: <b>CONNECTED</b><br><code>{{listenAddress}}:{{listenPort}}</code></div>
            <div class="row">LAN bridge -&gt; BeamNG: <b>{{statusText}}</b><br><code>127.0.0.1:{{upstreamPort}}</code></div>
            {{action}}{{tokenHint}}</main></body></html>
            """;
        await WriteResponseAsync(stream, "200 OK", html, cancellationToken, "text/html; charset=utf-8");
    }

    private static string ProgramTargetPath() => "/ui/modules/apps/TaxiDriverHUD/external/index.html";

    private static async Task<byte[]> ReadHeaderAsync(NetworkStream stream, CancellationToken cancellationToken)
    {
        using var memory = new MemoryStream();
        var buffer = new byte[4096];
        while (memory.Length < MaximumHeaderBytes)
        {
            var count = await stream.ReadAsync(buffer, cancellationToken);
            if (count == 0) break;
            memory.Write(buffer, 0, count);
            var value = memory.GetBuffer();
            var length = (int)memory.Length;
            for (var index = Math.Max(3, length - count - 3); index < length; index++)
            {
                if (value[index - 3] == 13 && value[index - 2] == 10 &&
                    value[index - 1] == 13 && value[index] == 10) return memory.ToArray();
            }
        }
        throw new IOException("HTTP header was incomplete or too large.");
    }

    private static Task WriteResponseAsync(NetworkStream stream, string status, string body,
        CancellationToken cancellationToken, string contentType = "text/plain; charset=utf-8")
    {
        var bytes = Encoding.UTF8.GetBytes(body);
        var header = Encoding.ASCII.GetBytes($"HTTP/1.1 {status}\r\nContent-Type: {contentType}\r\nContent-Length: {bytes.Length}\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n");
        return WritePartsAsync(stream, header, bytes, cancellationToken);
    }

    private static async Task WritePartsAsync(NetworkStream stream, byte[] header, byte[] body,
        CancellationToken cancellationToken)
    {
        await stream.WriteAsync(header, cancellationToken);
        await stream.WriteAsync(body, cancellationToken);
    }

    public void Dispose()
    {
        lifetime.Cancel();
        listener.Stop();
        lifetime.Dispose();
    }
}
