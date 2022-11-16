	using support;
	using types;

	public class BunnymarkParticleFx : GameObjectScript
	{
		private FactoryBasedBunnymark _bunnymark;


		protected override void init()
		{
			Particlefx.play("#bunnies");
		}


		protected override void update(float dt)
		{
			Label.set_text("#label", $"Bunnies 15000 FPS:{FPS.Fps}");
		}
		
		
		protected override void final()
		{
			Bunnymark.Reset();
		}
	}