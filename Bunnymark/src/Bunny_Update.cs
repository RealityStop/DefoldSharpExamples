	using support;
	using types;

	public class Bunny_Update : GameObjectScript
	{
		private double velocity = -Math.random(100);

		protected override void init()
		{
			Gameobject.Position = new Vector2(Math.random(640), Math.random(1000, 1100));
		}


		protected override void update(float dt)
		{
			GameObjectReference.CurrentGameObject = Gameobject;
			velocity -= 1200 * dt;

			var pos = Gameobject.Position;
			pos.y = pos.y + velocity * dt;
			if (pos.y < 60)
			{
				velocity = -velocity;
				pos.y = 60;
			}

			Gameobject.Position = pos;
			GameObjectReference.CurrentGameObject = null;
		}
	}
