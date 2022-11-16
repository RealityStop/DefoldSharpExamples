using support;
using types;

public class Player : GameObjectScript
{
	private readonly Vector2 _input = new Vector2();
	private readonly float _speed = 50;
	private bool _firing;
	private Vector2 _movementDirection = new Vector2(0, -1);
	private bool _moving;
	private Factory _rocketFactory;


	protected override void init()
	{
		_rocketFactory = Gameobject.Component<Factory>("rocketfactory");

		RequestInput();
	}


	protected override bool on_input(Hash action_id, dynamic action)
	{
		if (action_id == CommonInput.Up)
			_input.y = 1;
		else if (action_id == CommonInput.Down)
			_input.y = -1;
		else if (action_id == CommonInput.Left)
			_input.x = -1;
		else if (action_id == CommonInput.Right)
			_input.x = 1;
		else if (action_id == CommonInput.Fire && action.pressed)
			_firing = true;

		_moving = _input.Magnitude() > 0;
		if (_moving)
			_movementDirection = _input.Normalize().ToVector2();

		return false;
	}


	protected override void update(float dt)
	{
		if (_moving)
			Go.set_position(Go.get_position() + _movementDirection * _speed * dt);

		if (_firing)
		{
			var angle = System.Math.Atan2(_movementDirection.y, _movementDirection.x);
			var rotation = Vmath.quat_rotation_z(angle);
			var props = new LuaTable();
			props.Add("Direction", _movementDirection);
			_rocketFactory.Create(null, rotation, props);
		}

		_input.x = 0;
		_input.y = 0;
		_moving = false;
		_firing = false; //Don't forget to turn off firing again!
	}
}