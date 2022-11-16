using System;
using System.Collections.Generic;
using types;

public class GuiBasedBunnymark : IBunnymark, IDisposable
{
	
	private readonly Action<GuiBunny> _bunnyInitializer;

	public List<GuiBunny> Bunnies = new List<GuiBunny>();

	public int BunnyCount =>  Bunnies.Count;

	public GuiBasedBunnymark(Action<GuiBunny> bunnyInitializer = null)
	{
		_bunnyInitializer = bunnyInitializer;
		Bunnymark.CurrentInstance = this;
	}


	public bool CreateBunny()
	{
		var box = Gui.new_box_node(Vmath.vector3(), Vmath.vector3());
		if (box != null)
		{
			Gui.set_size_mode(box, SizeMode.SIZE_MODE_AUTO);
			Gui.set_texture(box, "bunnymark");
			Gui.play_flipbook(box, Bunnymark.RandomImage());
			var newBunny = new GuiBunny(box);
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


	protected virtual void InitializeBunny(GuiBunny newBunny)
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