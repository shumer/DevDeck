namespace DevDeck.Shell;

public sealed class CardMoveTracker
{
    private int programmaticMoves;
    private bool dragging;
    private bool pendingDpiChange;
    private bool pendingSystemMove;
    private bool reportScheduled;

    public void BeginProgrammaticMove()
    {
        programmaticMoves++;
    }

    public void EndProgrammaticMove()
    {
        programmaticMoves = Math.Max(0, programmaticMoves - 1);
    }

    public void BeginDrag()
    {
        dragging = true;
        pendingDpiChange = false;
        pendingSystemMove = false;
    }

    public bool DpiChanged()
    {
        if (!dragging)
        {
            return true;
        }
        pendingDpiChange = true;
        return false;
    }

    public bool TakeDelayedDpiChange()
    {
        var delayed = pendingDpiChange;
        pendingDpiChange = false;
        return delayed;
    }

    public bool EndDrag()
    {
        var shouldReport = dragging && programmaticMoves == 0;
        dragging = false;
        pendingSystemMove = false;
        reportScheduled = false;
        return shouldReport;
    }

    public bool PositionChanged()
    {
        if (programmaticMoves > 0 || dragging)
        {
            return false;
        }
        pendingSystemMove = true;
        if (reportScheduled)
        {
            return false;
        }
        reportScheduled = true;
        return true;
    }

    public bool FlushSystemMove()
    {
        reportScheduled = false;
        var shouldReport = pendingSystemMove && programmaticMoves == 0 && !dragging;
        pendingSystemMove = false;
        return shouldReport;
    }
}
