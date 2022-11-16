using support;
using types;

public class RocketProperties : AnimatableProperties
{
	public Vector2 Direction = new Vector2();
}

public class Rocket : GameObjectScript<RocketProperties>
{
	private bool _isExploded;
	private float _life = 1;
	private readonly float _speed = 200;
	private Sprite _sprite;

	
	private static Hash explosion = Defold.hash("explosion");

	protected override void init()
	{
		_sprite = Gameobject.Component<Sprite>("sprite");
	}


	protected override void update(float dt)
	{
		//If we've already exploded, there's no need for any movement or secondary explosions.
		if (_isExploded)
			return;

		//Movement
		Go.set_position(Go.get_position() + Properties.Direction * _speed * dt);

		//Life update and explosion
		_life -= dt; //Decrease the life timer with delta time. It will decrease with 1.0 per second.
		if (_life < 0)
			Explode();
	}


	private void Explode()
	{
		_isExploded = true;
		Go.set_rotation(
			new Quaternion()); //Set the game object rotation to 0, otherwise the explosion graphics will be rotated

		_sprite.PlayFlipbook(explosion);
	}


	protected override void on_message(Hash message_id, object message, Hash sender)
	{
		if (Message.IsMessage<Sprite.animation_done_message>(message_id, message, out var doneMessage))
			Go.delete();

		if (Message.IsMessage<Physics.collision_response_message>(message_id, message, out var impl))
		{
			//The engine sends a message called "collision_response" when the shapes collide, if the group and mask pairing is correct.
			Explode();
			Go.delete(impl.other_id, true);
			Message.postMessage("/gui#ui", new AddScoreMessage { scoreChange = 100 });
		}
	}
}