using System.Diagnostics;
using support;
using types;

namespace Scenes
{
	public class BunnymarkAnimateMultiple : GameObjectScript
	{
		private static Url[] collections =
		{
			Msg.url("multiple:/go#proxy_one"),
			Msg.url("multiple:/go#proxy_two"),
			Msg.url("multiple:/go#proxy_three")
		};

		private int _currentCollection = -1;

		protected override void init()
		{
			this.RequestInput();
			LoadNextCollection();
		}


		protected override void final()
		{
			Bunnymark.Reset();
		}


		private void LoadNextCollection()
		{
			if (_currentCollection < collections.Length)
			{
				_currentCollection++;

				//you could also trim the above urls to just component references
				//and use the GameObject.Component notation.  But this demonstrates how to use a custom locator
				var proxy = Component.At<CollectionProxy>(Locator.AtUrl(collections[_currentCollection]));
				proxy.LoadAsync();
			}
			else
			{
				Defold.pprint("No more collections to load");
			}
		}


		protected override void update(float dt)
		{
			Label.set_text("#label", $"Bunnies {Bunnymark.BunnyCount} FPS:{FPS.Fps}");
		}


		protected override void on_message(Hash message_id, object message, Hash sender)
		{
			if (Message.IsMessage<CollectionProxy.proxy_loaded_message>(message_id, message, out var impl))
				Message.post(sender, "enable");
			else if (message_id == Defold.hash("collection_full"))
				LoadNextCollection();
		}
	}
}