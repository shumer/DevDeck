using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Text;
using QRCoder;

namespace DevDeck.Windows.Core;

public sealed record LanInterface(string Name, string Description, NetworkInterfaceType Type, bool Up, bool HasGateway, string[] Addresses);
public enum PhoneLinkIssue { None, NotRunning, NoSite, InvalidURL, NoLAN, RoutedHost, Unavailable }
public sealed record PhoneLinkResult(Uri? Address, PhoneLinkIssue Issue);

public static class PhoneLink
{
    public static string? Address(IEnumerable<LanInterface> interfaces) => interfaces
        .Where(item => item.Up && (item.Type is NetworkInterfaceType.Wireless80211 or NetworkInterfaceType.Ethernet)
            && !new[] { "virtual", "vethernet", "hyper-v", "wsl", "docker", "vpn", "wireguard", "tailscale", "zerotier", "vmware", "loopback", "tap-windows" }
                .Any(part => (item.Name + " " + item.Description).Contains(part, StringComparison.OrdinalIgnoreCase)))
        .OrderByDescending(item => item.Type == NetworkInterfaceType.Wireless80211).ThenByDescending(item => item.HasGateway)
        .SelectMany(item => item.Addresses).FirstOrDefault(UsableAddress);

    public static string? CurrentAddress()
    {
        try { return Address(NetworkInterface.GetAllNetworkInterfaces().Select(item => new LanInterface(item.Name, item.Description,
            item.NetworkInterfaceType, item.OperationalStatus == OperationalStatus.Up,
            item.GetIPProperties().GatewayAddresses.Any(gateway => gateway.Address.AddressFamily == AddressFamily.InterNetwork),
            item.GetIPProperties().UnicastAddresses.Select(address => address.Address.ToString()).ToArray()))); }
        catch (NetworkInformationException) { return null; }
    }

    public static Uri? Rewrite(string? site, bool running, string? address)
    {
        return Resolve(site, running, address).Address;
    }

    public static PhoneLinkResult Resolve(string? site, bool running, string? address, string? phoneURL = null)
    {
        if (!running) return new(null, PhoneLinkIssue.NotRunning);
        if (!string.IsNullOrWhiteSpace(phoneURL)) return ValidPhoneURL(phoneURL)
            ? new(new Uri(phoneURL), PhoneLinkIssue.None) : new(null, PhoneLinkIssue.InvalidURL);
        if (string.IsNullOrWhiteSpace(site)) return new(null, PhoneLinkIssue.NoSite);
        if (!ValidURL(site, out var url)) return new(null, PhoneLinkIssue.InvalidURL);
        var host = url.Host.Trim('[', ']');
        var loopback = IsLoopback(host);
        if (!loopback && host != address) return new(null, PhoneLinkIssue.RoutedHost);
        if (address is null || !UsableAddress(address)) return new(null, PhoneLinkIssue.NoLAN);
        var rewritten = new UriBuilder(url) { Host = address }.Uri;
        return Encoding.UTF8.GetByteCount(rewritten.AbsoluteUri) <= 2048 ? new(rewritten, PhoneLinkIssue.None) : new(null, PhoneLinkIssue.InvalidURL);
    }

    // An explicit URL is supplied by the user after configuring LAN/DNS/sharing. Do not infer it
    // from a Host-routed DDEV address, or silently publish a WSL service on the physical network.
    public static bool ValidPhoneURL(string? value)
    {
        if (string.IsNullOrEmpty(value)) return true;
        if (!ValidURL(value, out var url)) return false;
        var host = url.Host.Trim('[', ']').TrimEnd('.');
        if (IsLoopback(host) || host.EndsWith(".localhost", StringComparison.OrdinalIgnoreCase) ||
            host.Equals("ddev.site", StringComparison.OrdinalIgnoreCase) || host.EndsWith(".ddev.site", StringComparison.OrdinalIgnoreCase)) return false;
        if (!IPAddress.TryParse(host, out var ip)) return true;
        if (ip.IsIPv4MappedToIPv6) ip = ip.MapToIPv4();
        return ip.AddressFamily == AddressFamily.InterNetwork ? UsableAddress(ip.ToString()) :
            !ip.Equals(IPAddress.IPv6Any) && !ip.IsIPv6LinkLocal && !ip.IsIPv6Multicast;
    }

    private static bool IsLoopback(string host) => host.Equals("localhost", StringComparison.OrdinalIgnoreCase) || host == "0.0.0.0" ||
        IPAddress.TryParse(host, out var ip) && IPAddress.IsLoopback(ip);
    private static bool ValidURL(string? value, out Uri url)
    {
        url = null!;
        return value is not null && !value.Any(char.IsControl) && Encoding.UTF8.GetByteCount(value) <= 2048 &&
            Uri.TryCreate(value, UriKind.Absolute, out url!) && url.Scheme is "http" or "https" &&
            url.UserInfo.Length == 0 && url.Port > 0 && Encoding.UTF8.GetByteCount(url.AbsoluteUri) <= 2048;
    }

    private static bool UsableAddress(string value)
    {
        if (!IPAddress.TryParse(value, out var address) || address.AddressFamily != AddressFamily.InterNetwork || IPAddress.IsLoopback(address)) return false;
        var bytes = address.GetAddressBytes();
        return bytes[0] is > 0 and < 224 && !(bytes[0] == 169 && bytes[1] == 254);
    }
}

public static class PhoneCode
{
    public static bool[][] Encode(Uri address)
    {
        if (address.Scheme is not ("http" or "https") || address.UserInfo.Length > 0 || Encoding.UTF8.GetByteCount(address.AbsoluteUri) > 2048)
            throw new ArgumentException("A bounded HTTP(S) phone link is required.", nameof(address));
        using var code = QRCodeGenerator.GenerateQrCode(address.AbsoluteUri, QRCodeGenerator.ECCLevel.M);
        return code.ModuleMatrix.Select(row => row.Cast<bool>().ToArray()).ToArray();
    }
}
