using types;

public static class CommonInput
{
	public static Hash Up { get; } = Defold.hash("up");
	public static Hash Down { get; } = Defold.hash("down");
	public static Hash Left { get; } = Defold.hash("left");
	public static Hash Right { get; } = Defold.hash("right");
	public static Hash Fire { get; } = Defold.hash("fire");

	public static Hash LeftClick { get; } = Defold.hash("left_click");

	public static Hash RightClick { get; } = Defold.hash("right_click");
}