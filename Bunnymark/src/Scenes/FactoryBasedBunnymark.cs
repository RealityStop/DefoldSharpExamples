using System;
using System.Collections.Generic;
using types;

public class FactoryBasedBunnymark : IBunnymark
{
	private readonly Factory _bunnyFactory;
	private readonly Action<GoBunny> _bunnyInitializer;


	
	public List<GoBunny> Bunnies = new List<GoBunny>();
	

	public FactoryBasedBunnymark(Factory sourceFactory, Action<GoBunny> bunnyInitializer = null)
	{
		_bunnyFactory = sourceFactory;
		_bunnyInitializer = bunnyInitializer;
		Bunnymark.CurrentInstance = this;
	}


	public bool CreateBunny()
	{
		var id = _bunnyFactory.Create();
		if (id != null)
		{
			var urlP1 = Msg.url(Msg.DefaultSocket, id, "sprite");


			var idP2 = Bunnymark.RandomImage();
			Sprite.play_flipbook(urlP1, idP2);
			var url = new Url(Msg.DefaultSocket, id, null);
			var newBunny = new GoBunny(url);
			Bunnies.Add(newBunny);
			InitializeBunny(newBunny);
			Bunnymark.BunnyCount++;
			return true;
		}
		else
		{
			Defold.pprint("Unable to create more bunnies");
			return false;
		}
	}


	protected virtual void InitializeBunny(GoBunny newBunny)
	{
		if (_bunnyInitializer != null)
			_bunnyInitializer(newBunny);
	}
	
	public bool Spawn(int count)
	{
		for (int i = 0; i < count; i++)
		{
			if (!CreateBunny())
				return false;
		}

		return true;
	}


	public void Dispose()
	{
		Bunnymark.CurrentInstance = null;
	}
}