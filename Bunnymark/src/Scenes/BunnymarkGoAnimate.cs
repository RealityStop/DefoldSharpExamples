	using support;
	using types;

	public class BunnymarkGoAnimate : GameObjectScript
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
			Go.set_position(new Vector3(Math.random(640), 1024,0), newBunny.url);
			Go.animate(newBunny.url, "position.y", GoPlaybackMode.PLAYBACK_LOOP_PINGPONG, 80, Easing.EASING_INQUAD, 2, Math.random());
		}


		protected override void update(float dt)
		{
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