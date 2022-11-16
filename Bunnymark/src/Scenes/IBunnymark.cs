using System;
using types;

public interface IBunnymark : IDisposable
{
	bool CreateBunny();
	bool Spawn(int count);
}