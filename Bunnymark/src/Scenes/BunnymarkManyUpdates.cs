using support;
using types;

public class BunnymarkManyUpdates : GameObjectScript
{
	private Hash touchHash = Defold.hash("touch");
	private Hash toggledebugHash = Defold.hash("toggledebug");
	
	private FactoryBasedBunnymark _bunnymark;
	

	protected override void init()
	{
		base.init();

		this.RequestInput();
		
		_bunnymark = new FactoryBasedBunnymark(Gameobject.Component<Factory>("factory"));
		_bunnymark.Spawn(500);
	}

	protected override void update(float dt)
	{
		base.update(dt);
		Label.set_text("#label", $"Bunnies {Bunnymark.BunnyCount} FPS:{FPS.Fps}");
	}


	protected override bool on_input(Hash action_id, dynamic action)
	{
		if (action_id == touchHash && action.released && action.y < 1030)
			_bunnymark.Spawn(500);

		if (action_id == toggledebugHash && action.released)
			Debug.ToggleEditorDebug();

		return false;
	}
	
	
	protected override void final()
	{
		Bunnymark.Reset();
	}
}