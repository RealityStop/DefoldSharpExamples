	using support;
	using types;

	public class BunnymarkGuiAnimate : GameObjectScript
	{
		private Hash touchHash = Defold.hash("touch");

		private GuiBasedBunnymark _bunnymark;
		private Factory _factory;


		protected override void init()
		{
			base.init();

			_bunnymark = new GuiBasedBunnymark(AnimateBunny);
			_factory = Gameobject.Component<Factory>("factory");
			this.RequestInput();
		}


		private void AnimateBunny(GuiBunny bunny)
		{
			Gui.set_position(bunny.node, new Vector2(Math.random(640), 1030));
			Gui.animate(bunny.node, "position.y", 80.0, Easing.EASING_INQUAD, 2.0, Math.random(), null, GuiPlaybackMode.PLAYBACK_LOOP_PINGPONG);
		}


		protected override void update(float dt)
		{
			Label.set_text("#label", $"Bunnies {_bunnymark.BunnyCount} FPS:{FPS.Fps}");
		}
		
		
	
		protected override bool on_input(Hash action_id, dynamic action)
		{
			if (action_id == touchHash && action.released && action.y < 1030)
				_factory.Create();

			return false;
		}
		
		
		protected override void final()
		{
			Bunnymark.Reset();
		}
	}