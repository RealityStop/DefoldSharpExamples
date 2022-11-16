using support;
using types;

namespace Scenes
{
	public class AnimateMultipleCollectionProps : AnimatableProperties
	{
		public int min_x = 0;
		public int max_x = 640;
	}
	
	public class BunnymarkAnimateMultipleCollection : GameObjectScript<AnimateMultipleCollectionProps>
	{
		private Hash touchHash = Defold.hash("touch");
		private FactoryBasedBunnymark _bunnymark;


		protected override void init()
		{
			this.RequestInput();
			var factory = Gameobject.Component<Factory>("factory");
			_bunnymark = new FactoryBasedBunnymark(factory, AnimateBunny);
			_bunnymark.Spawn(500);
		}


		private void AnimateBunny(GoBunny newBunny)
		{
			Go.set_position(new Vector3(Math.random(Properties.min_x, Properties.max_x), 1024,0), newBunny.url);
			Go.animate(newBunny.url, "position.y", GoPlaybackMode.PLAYBACK_LOOP_PINGPONG, 80, Easing.EASING_INQUAD, 2, Math.random());
		}


		protected override bool on_input(Hash action_id, dynamic action)
		{
			if (action_id == touchHash && action.released && action.y < 1030)
				if (!_bunnymark.Spawn(500))
				{
					Defold.pprint("Unable to create more bunnies");
					this.ReleaseInput();
					Msg.post("multiple:/go", "collection_full");
				}

			return false;
		}
	}
}