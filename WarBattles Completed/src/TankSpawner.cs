using support;
using types;

public class SpawnSettings : AnimatableProperties
	{
		public double delay = 2;
		public int burst = 300;
		public double minFPS = 50;
	}

public class TankSpawner : GameObjectScript<SpawnSettings>
{
	private double _timer  = 1;
	private Factory _tankFactory;
	private int _tankCount;


	protected override void init()
	{
		_tankFactory = Gameobject.Component<Factory>("tankFactory");

		for (int i = 0; i < Properties.burst; i++)
		{
			SpawnTank();
		}
	}


	protected override void update(float dt)
	{
		 
		if (FPS.Fps < Properties.minFPS)
			_timer = Properties.delay;
		else
		{
			_timer -= dt;
			if (_timer <= 0)
			{
				SpawnTank();
				_timer = Properties.delay;
			}
		}
	}


	private void SpawnTank()
	{
		_tankFactory.Create();
		Message.postMessage("/gui#ui", new TankCountMessage() { newCount = ++_tankCount});
	}
}