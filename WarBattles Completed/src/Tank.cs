using System;
using support;
using types;

public class TankProperties : AnimatableProperties
{
	public double speed = 50;
}

public class Tank : GameObjectScript<TankProperties>
{
	private static Random _rand = new Random();
	private Vector3 targetPos = new Vector3();


	protected override void update(float dt)
	{
		GameObjectReference.CurrentGameObject = this.Gameobject;
		var gameobject = Gameobject;
		var curPos = gameobject.WorldPosition;
		
		var todestination = targetPos - curPos;
		if (todestination.MagnitudeSqr() > 1)
			gameobject.Position = curPos + todestination.Normalize() * Properties.speed * dt;
		else
		{
			targetPos = new Vector2(Math.random(400), Math.random(400));
			//targetPos = new Vector2((float)_rand.NextDouble()*400, (float)_rand.NextDouble()*400);
		}

		GameObjectReference.CurrentGameObject = null;
	}
}