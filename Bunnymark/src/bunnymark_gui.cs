using System;
using support;
using types;

public class Bunnymark_GUI : GUIScript
{
	private bool _menuEnabled;


	private Node test_root_node;
	private Node toggle_profiler_node;
	private Node back_node;
	private Node menu_root_node;
	private Node go_animate_node;
	private Node go_animate_multiple_node;
	private Node update_single_node;
	private Node update_many_node;
	private Node particlefx_node;
	private Node gui_animate_node;
	private string _currentProxy;
	private Node FPS_node;


	protected override void init()
	{
		Math.randomseed(OS.clock());
		this.RequestInput();

		var dataTable = new LuaTable();
		dataTable.Add("color", new Vector4(0.4, 0.5, 0.8, 1));
		Message.post("@render:", "clear_color", dataTable);

		_menuEnabled = true;


		test_root_node = GetNode("test_root");
		toggle_profiler_node = GetNode("toggle_profiler");
		back_node = GetNode("back");
		test_root_node.SetEnabled(false);

		menu_root_node = GetNode("menu_root");
		go_animate_node = GetNode("go_animate");
		go_animate_multiple_node = GetNode("go_animate_multiple");
		update_single_node = GetNode("update_single");
		update_many_node = GetNode("update_many");
		particlefx_node = GetNode("particlefx");
		gui_animate_node = GetNode("gui_animate");



		string version = ((dynamic)Sys.get_engine_info()).version;
		GetNode<TextNode>("version").SetText(version);
	}


	protected override void on_message(Hash message_id, dynamic message, Hash sender)
	{
		if (message_id == Defold.hash("proxy_loaded"))
		{
			Msg.post(sender, "enable");
			_menuEnabled = false;
			test_root_node.SetEnabled(true);
			menu_root_node.SetEnabled(false);
		}
		else if (message_id == Defold.hash("proxy_unloaded"))
		{
			_menuEnabled = true;
			test_root_node.SetEnabled(false);
			menu_root_node.SetEnabled(true);
		}
	}


	protected override bool on_input(Hash action_id, dynamic action)
	{
		if (action_id == Defold.hash("touch") && action.released)
		{
			if (_menuEnabled)
			{
				if (Gui.pick_node(go_animate_node, action.x, action.y))
					Load("#go_animate_proxy");
				else if (Gui.pick_node(update_single_node, action.x, action.y))
					Load("#update_single_proxy");
				else if (Gui.pick_node(update_many_node, action.x, action.y))
					Load("#update_many_proxy");
				else if (Gui.pick_node(particlefx_node, action.x, action.y))
					Load("#particlefx_proxy");
				else if (Gui.pick_node(go_animate_multiple_node, action.x, action.y))
					Load("#go_animate_multiple_proxy");
				else if (Gui.pick_node(gui_animate_node, action.x, action.y))
					Load("#gui_animate_proxy");
			}
			else
			{
				if (Gui.pick_node(back_node, action.x, action.y))
					Msg.post(_currentProxy, "unload");
				else if (Gui.pick_node(toggle_profiler_node, action.x, action.y))
					Msg.post("@system:", "toggle_profile");
			}
		}

		return false;
	}


	private void Load(string proxy_url)
	{
		Msg.post(proxy_url, "load");
		_currentProxy = proxy_url;
	}
}