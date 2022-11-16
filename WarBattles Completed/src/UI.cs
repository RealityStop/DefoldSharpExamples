using support;
using types;

public class AddScoreMessage : MessageImplementation
{
	public float scoreChange;


	public override Hash FetchCode()
	{
		return nameof(AddScoreMessage);
	}
}


public class TankCountMessage : MessageImplementation
{
	public int newCount;
	
	public override Hash FetchCode() => "tankcount";
}


public class MainUI : GUIScript
{
	private Node _scoreNode;
	private float _scoreTotal;
	private Node _fpsNode;
	private Node _tankCountNode;


	protected override void init()
	{
		_scoreNode = Gui.get_node("score");
		_fpsNode = Gui.get_node("fps");
		_tankCountNode = Gui.get_node("tankCount");
	}


	protected override void update(float dt)
	{
		Gui.set_text(_fpsNode, "FPS: " + FPS.Fps);
	}


	protected override void on_message(Hash message_id, object message, Hash sender)
	{
		// A special API is provided to detect and allow us to operate on the data in a type-safe way.
		// If the reconstruct metadata is false (default), no actual conversion takes place.  When true, it
		// will create a new instance of the message and copy the data from the message table.  Most of the time this
		// isn't needed, but it is left to the developer's discretion.
		if (Message.IsMessage<AddScoreMessage>(message_id, message, out var impl))
		{
			_scoreTotal += impl.scoreChange;
			Gui.set_text(_scoreNode, "SCORE: " + _scoreTotal);
		}

		if (Message.IsMessage<TankCountMessage>(message_id, message, out var tankCountData))
		{
			Gui.set_text(_tankCountNode, "Tanks: " + tankCountData.newCount);
		}
	}
}