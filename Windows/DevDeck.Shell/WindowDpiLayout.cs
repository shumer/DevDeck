namespace DevDeck.Shell;

public static class WindowDpiLayout
{
    public static double LocalDipsForPrimaryDips(
        double value,
        double primaryScale,
        double windowScale)
    {
        if (primaryScale <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(primaryScale));
        }
        if (windowScale <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(windowScale));
        }

        return value * primaryScale / windowScale;
    }
}
