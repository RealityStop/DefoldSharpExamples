using support;
using types;

public class RocketProperties : AnimatableProperties
{
	public Vector2 Direction = new Vector2();
}

public class Rocket : GameObjectScript<RocketProperties>
{
	private float _speed = 200;
	private float _life = 1;
	private bool _isExploded;


	protected override void update(float dt)
	{
		//If we've already exploded, there's no need for any movement or secondary explosions.
		if (_isExploded)
			return;

		//Movement
		go.set_position(go.get_position() + Properties.Direction * _speed * dt);

		//Life update and explosion
		_life -= dt; //Decrease the life timer with delta time. It will decrease with 1.0 per second.
		if (_life < 0)
			Explode();
	}


	private void Explode()
	{
		_isExploded = true;
		go.set_rotation(
			new Quaternion()); //Set the game object rotation to 0, otherwise the explosion graphics will be rotated

		LuaTable table = new LuaTable();
		table.Add("id", Defold.hash("explosion"));

		msg.post("#sprite", "play_animation", table);
	}


	protected override void on_message(Hash message_id, dynamic message, object sender)
	{
		if (message_id == Defold.hash("animation_done"))
			go.delete();
		
		//The engine sends a message called "collision_response" when the shapes collide, if the group and mask pairing is correct.
		if (message_id == Defold.hash("collision_response"))
		{
			Explode();
			go.delete(message.other_id, true);
			Message.postMessage("/gui#ui", new AddScoreMessage(){scoreChange = 100});
		}
	}
}