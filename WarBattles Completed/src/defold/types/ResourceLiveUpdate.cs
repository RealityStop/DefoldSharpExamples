namespace types
{
	/// <summary>
	/// @CSharpLua.Ignore
	/// </summary>
	public enum ResourceLiveUpdate
	{
		LIVEUPATE_OK = 0,
		LIVEUPATE_INVALID_RESOURCE = 1,
		LIVEUPATE_VERSION_MISMATCH = 2,
		LIVEUPATE_ENGINE_VERSION_MISMATCH = 3,
		LIVEUPATE_SIGNATURE_MISMATCH = 4,
		LIVEUPDATE_BUNDLED_RESOURCE_MISMATCH = 5,
		LIVEUPDATE_FORMAT_ERROR = 6,
	}
}
