using System.Globalization;
using System.Text;
using System.Text.Json;

namespace DevDeck.Shell;

public static class DeveloperCommands
{
    public static async Task<int> RunAsync(string enginePath, DeveloperRequest request)
    {
        await using var engine = new EngineClient(enginePath);
        var answer = new TaskCompletionSource<DeckEvent>(TaskCreationOptions.RunContinuationsAsynchronously);
        const string requestId = "2";
        engine.EventReceived += message =>
        {
            if (message.Event == "settings.answered" && message.Id == requestId)
            {
                answer.TrySetResult(message);
            }
        };
        engine.Start();
        await engine.SendAsync(
            ProtocolWriter.SessionStart(
                "1",
                CultureInfo.CurrentUICulture.Name,
                DisplayProvider.Current()));
        await engine.SendAsync(ProtocolWriter.Settings(requestId, RequestJson(request)));

        var finished = await Task.WhenAny(answer.Task, engine.Completion);
        if (finished != answer.Task)
        {
            return 1;
        }

        Console.WriteLine((await answer.Task).RawLine);
        await engine.SendAsync(ProtocolWriter.SessionStop("3"));
        return 0;
    }

    private static string RequestJson(DeveloperRequest request)
    {
        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(stream))
        {
            writer.WriteStartObject();
            writer.WritePropertyName(
                request.Kind == DeveloperRequestKind.AddProject
                    ? "addLocalProject"
                    : "removeLocalProject");
            writer.WriteStartObject();
            writer.WriteString(
                request.Kind == DeveloperRequestKind.AddProject ? "folder" : "id",
                request.Value);
            writer.WriteEndObject();
            writer.WriteEndObject();
        }

        return Encoding.UTF8.GetString(stream.ToArray());
    }
}
