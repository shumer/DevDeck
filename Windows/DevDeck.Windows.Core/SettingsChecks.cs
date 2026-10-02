using System.Text;

namespace DevDeck.Windows.Core;

public static class SettingsChecks
{
    public static bool Valid(ProjectCheckSummary? summary, double? checkedAt) =>
        (checkedAt is null || double.IsFinite(checkedAt.Value) && checkedAt.Value is >= 0 and <= 253402300799) &&
        (summary is null || summary.Tone is "good" or "busy" or "bad" or "idle" &&
            summary.State is not null && Encoding.UTF8.GetByteCount(summary.State) <= 512 && !summary.State.Any(char.IsControl) &&
            summary.Detail is not null && Encoding.UTF8.GetByteCount(summary.Detail) <= 16384 &&
            !summary.Detail.Any(value => char.IsControl(value) && value is not ('\n' or '\r' or '\t')));
}
