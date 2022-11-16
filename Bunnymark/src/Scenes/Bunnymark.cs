using types;


public static class Bunnymark
{
	public static readonly Hash[] BunnyImages =
	{
		"rabbitv3_batman",
		"rabbitv3_bb8",
		"rabbitv3",
		"rabbitv3_ash",
		"rabbitv3_frankenstein",
		"rabbitv3_neo",
		"rabbitv3_sonic",
		"rabbitv3_spidey",
		"rabbitv3_stormtrooper",
		"rabbitv3_superman",
		"rabbitv3_tron",
		"rabbitv3_wolverine",
	};

	public static Hash RandomImage()
	{
		return BunnyImages[Math.random(0, BunnyImages.Length -1)];
	}


	public static IBunnymark CurrentInstance;
	public static int BunnyCount { get; set; }


	public static void Reset()
	{
		BunnyCount = 0;
		CurrentInstance = null;
	}
}