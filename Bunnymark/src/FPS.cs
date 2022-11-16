using support;

public class FPSProperties : AnimatableProperties
{
	public int sampleCount = 60;
}


public class FPS : GameObjectScript<FPSProperties>
{
	public class SimpleMovingAverage
	{
		private readonly int _k;
		private readonly double[] _values;

		private int _index = 0;
		private double _sum = 0;


		public SimpleMovingAverage(uint k)
		{
			_k = (int)k;
			_values = new double[k];
		}


		public double Update(double nextInput)
		{
			// calculate the new sum
			_sum = _sum - _values[_index] + nextInput;

			// overwrite the old value with the new one
			_values[_index] = nextInput;

			// increment the index (wrapping back to 0)
			_index = (_index + 1) % _k;

			// calculate the average
			return (_sum) / _k;
		}
	}


	private SimpleMovingAverage sma;


	public static bool LowFPS { get; private set; }
	public static double Fps { get; private set; }


	protected override void init()
	{
		sma = new SimpleMovingAverage(60);
	}


	protected override void update(float dt)
	{
		Fps = 1/sma.Update(dt);
		LowFPS = Fps < 60;
	}
}