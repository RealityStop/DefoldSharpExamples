using support;
using types;

public class AddScoreMessage : CustomMessageImplementation
{
	public float scoreChange;
}

public class MainUI : GUIScript
{
	private Node _scoreNode;
	private float _scoreTotal;


	protected override void init()
	{
		_scoreNode = gui.get_node("score");
	}


	protected override void on_message(Hash message_id, object message, object sender)
	{
		// A special API is provided to detect and allow us to operate on the data in a type-safe way.
		// If the reconstruct metadata is false (default), no actual conversion takes place.  When true, it
		// will create a new instance of the message and copy the data from the message table.  Most of the time this
		// isn't needed, but it is left to the developer's discretion.
		if (Message.IsMessage<AddScoreMessage>(message_id, message, out var impl))
		{
			_scoreTotal += impl.scoreChange;
			gui.set_text(_scoreNode, "SCORE: " + _scoreTotal);
		}
	}
}