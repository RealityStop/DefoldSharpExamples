using support;
using types;

public class BunnymarkSingleUpdate : GameObjectScript
{
	private Hash touchHash = Defold.hash("touch");

	private FactoryBasedBunnymark _bunnymark;


	protected override void init()
	{
		base.init();
		this.RequestInput();

		_bunnymark = new FactoryBasedBunnymark(Gameobject.Component<Factory>("factory"), OnBunnyCreate);
		_bunnymark.Spawn(500);
	}


	protected void OnBunnyCreate(GoBunny newBunny)
	{
		newBunny.Position = new Vector3(
			Math.random(640),
			Math.random(930, 1024),
			0);

		newBunny.Velocity = Math.random(200);
	}


	protected override void update(float dt)
	{
		foreach (var bunny in _bunnymark.Bunnies)
		{
			bunny.Velocity -= 1200 * dt;
			bunny.Position.y += bunny.Velocity * dt;

			if (bunny.Position.y < 50)
			{
				bunny.Position.y = 50;
				bunny.Velocity = -bunny.Velocity;
			}

			Go.set_position(bunny.Position, bunny.url);
		}

		Label.set_text("#label", $"Bunnies {Bunnymark.BunnyCount} FPS:{FPS.Fps}");
	}


	protected override bool on_input(Hash action_id, dynamic action)
	{
		if (action_id == touchHash && action.released && action.y < 1030)
			_bunnymark.Spawn(500);

		return false;
	}
	
	
	protected override void final()
	{
		Bunnymark.Reset();
	}
}