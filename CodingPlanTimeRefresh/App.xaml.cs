namespace CodingPlanTimeRefresh;

public partial class App : Application
{
    public static Window? MainWindow { get; private set; }
    public static AppConfig Config { get; private set; } = new();

    public App()
    {
        InitializeComponent();
    }

    protected override Window CreateWindow(IActivationState? activationState)
    {
        Config = ConfigService.Load();
        LocalizationService.Initialize(Config.Language);

        var window = new Window(new MainPage())
        {
            Title = "Coding Plan Time Refresh",
            Width = ConfigService.ExpandedWidth,
            Height = Config.IsCollapsed ? ConfigService.CollapsedHeight : ConfigService.ExpandedHeight,
            MinimumWidth = ConfigService.ExpandedWidth,
            MinimumHeight = ConfigService.CollapsedHeight,
            MaximumWidth = ConfigService.ExpandedWidth,
            MaximumHeight = ConfigService.ExpandedHeight
        };
        //var displayInfo = DeviceDisplay.Current.MainDisplayInfo;
        
        //// 计算屏幕可用区域（去掉 Density 换算成逻辑像素）
        //double screenWidth = displayInfo.Width / displayInfo.Density;
        //double screenHeight = displayInfo.Height / displayInfo.Density;

        //window.X = (screenWidth - window.Width) / 2;
        //window.Y = (screenHeight - window.Height) / 2;
        MainWindow = window;

#if WINDOWS
		window.Created += OnWindowsWindowCreated;
#elif MACCATALYST
        window.Created += OnMacWindowCreated;
#endif

        return window;
    }

#if WINDOWS
	private void OnWindowsWindowCreated(object? sender, EventArgs e)
	{
		if (MainWindow?.Handler?.PlatformView is Microsoft.UI.Xaml.Window winUiWindow)
		{
			var appWindow = winUiWindow.AppWindow;

			// Center on screen
			var screenArea = Microsoft.UI.Windowing.DisplayArea.Primary.WorkArea;
			var x = (screenArea.Width - appWindow.Size.Width) / 2;
			var y = (screenArea.Height - appWindow.Size.Height) / 2;
			appWindow.Move(new Windows.Graphics.PointInt32(x, y));

			if (appWindow.Presenter is Microsoft.UI.Windowing.OverlappedPresenter presenter)
			{
				presenter.IsAlwaysOnTop = Config.IsAlwaysOnTop;
				presenter.IsResizable = false;
				presenter.IsMaximizable = false;
			}

			// Prevent double-click title bar maximize
			appWindow.Changed += (s, args) =>
			{
				if (s.Presenter is Microsoft.UI.Windowing.OverlappedPresenter p
					&& p.State == Microsoft.UI.Windowing.OverlappedPresenterState.Maximized)
				{
					p.Restore();
				}
			};
		}
	}

	public static void ApplyAlwaysOnTop(bool onTop)
	{
		if (MainWindow?.Handler?.PlatformView is Microsoft.UI.Xaml.Window winUiWindow)
		{
			if (winUiWindow.AppWindow.Presenter is Microsoft.UI.Windowing.OverlappedPresenter presenter)
			{
				presenter.IsAlwaysOnTop = onTop;
			}
		}
	}

	public static void ResizeWindow(double height)
	{
		if (MainWindow?.Handler?.PlatformView is Microsoft.UI.Xaml.Window winUiWindow)
		{
			var appWindow = winUiWindow.AppWindow;
			// Calculate DPI scale from current window size
			var scale = (double)appWindow.Size.Height / MainWindow.Height;
			var pixelHeight = (int)(height * scale);
			appWindow.Resize(new Windows.Graphics.SizeInt32(appWindow.Size.Width, pixelHeight));
		}
		if (MainWindow != null)
				MainWindow.Height = height;
	}
#elif MACCATALYST
    private const double MacTitleBarHeight = 28.0;

    [System.Runtime.InteropServices.DllImport("/usr/lib/libobjc.A.dylib", EntryPoint = "objc_msgSend")]
    private static extern IntPtr ObjCRet(IntPtr self, IntPtr cmd);

    [System.Runtime.InteropServices.DllImport("/usr/lib/libobjc.A.dylib", EntryPoint = "objc_msgSend")]
    private static extern IntPtr ObjCRetArg(IntPtr self, IntPtr cmd, IntPtr arg);

    [System.Runtime.InteropServices.DllImport("/usr/lib/libobjc.A.dylib", EntryPoint = "objc_msgSend")]
    private static extern void ObjCVoid(IntPtr self, IntPtr cmd, IntPtr arg);

    [System.Runtime.InteropServices.DllImport("/usr/lib/libobjc.A.dylib", EntryPoint = "objc_msgSend")]
    private static extern void ObjCVoidLong(IntPtr self, IntPtr cmd, long arg);

    [System.Runtime.InteropServices.DllImport("/usr/lib/libobjc.A.dylib", EntryPoint = "objc_msgSend")]
    private static extern void ObjCVoidDoubles(IntPtr self, IntPtr cmd, double a, double b);

    [System.Runtime.InteropServices.DllImport("/usr/lib/libobjc.A.dylib")]
    private static extern IntPtr sel_registerName(string name);

    [System.Runtime.InteropServices.DllImport("/usr/lib/libobjc.A.dylib")]
    private static extern IntPtr objc_getClass(string name);

    [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
    private struct DisplayRect { public double X, Y, Width, Height; }

    [System.Runtime.InteropServices.DllImport("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")]
    private static extern DisplayRect CGDisplayBounds(uint display);

    [System.Runtime.InteropServices.DllImport("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")]
    private static extern uint CGMainDisplayID();

    public static void ApplyAlwaysOnTop(bool isAlwaysOnTop)
    {
        // 通过 NSApplication 直接设置 NSWindow level
        var nsAppClass = objc_getClass("NSApplication");
        if (nsAppClass == IntPtr.Zero) return;
        var sharedApp = ObjCRet(nsAppClass, sel_registerName("sharedApplication"));
        if (sharedApp == IntPtr.Zero) return;
        var nsWindows = ObjCRet(sharedApp, sel_registerName("windows"));
        if (nsWindows == IntPtr.Zero) return;

        var count = (int)ObjCRet(nsWindows, sel_registerName("count"));
        for (int i = 0; i < count; i++)
        {
            var nsWindow = ObjCRetArg(nsWindows, sel_registerName("objectAtIndex:"), (IntPtr)i);
            // NSFloatingWindowLevel = 3, NSNormalWindowLevel = 0
            ObjCVoidLong(nsWindow, sel_registerName("setLevel:"), isAlwaysOnTop ? 3L : 0L);
        }
    }

    private void OnMacWindowCreated(object? sender, EventArgs e)
    {
            MainThread.BeginInvokeOnMainThread(async () =>
        {
            await Task.Delay(100);

            var desiredWidth = ConfigService.ExpandedWidth;
            var desiredHeight = Config.IsCollapsed
                ? ConfigService.CollapsedHeight
                : ConfigService.ExpandedHeight;

            var nsWindow = GetFirstNSWindow();
            if (nsWindow != IntPtr.Zero)
            {
                // 禁止 macOS 自动恢复窗口位置
                var nsStringClass = objc_getClass("NSString");
                var emptyStr = ObjCRet(nsStringClass, sel_registerName("string"));
                ObjCVoid(nsWindow, sel_registerName("setFrameAutosaveName:"), emptyStr);

                // 先设置 MAUI 属性，再做原生定位，避免 MAUI 覆盖居中位置
                if (MainWindow != null)
                {
                    MainWindow.Width = desiredWidth;
                    MainWindow.Height = desiredHeight - MacTitleBarHeight;
                }

                // 原生设置内容尺寸和居中定位（最后执行，覆盖 MAUI 可能的侧影响）
                var contentHeight = desiredHeight - MacTitleBarHeight;
                ObjCVoidDoubles(nsWindow, sel_registerName("setContentSize:"), desiredWidth, contentHeight);

                var screen = CGDisplayBounds(CGMainDisplayID());
                var totalH = contentHeight + MacTitleBarHeight;
                var topX = (screen.Width - desiredWidth) / 2;
                var topY = (screen.Height + totalH) / 2;
                ObjCVoidDoubles(nsWindow, sel_registerName("setFrameTopLeftPoint:"), topX, topY);
            }

            DisableMacZoomButton();
            ApplyAlwaysOnTop(Config.IsAlwaysOnTop);
        });
    }

    private void DisableMacZoomButton()
    {
        var nsAppClass = objc_getClass("NSApplication");
        if (nsAppClass == IntPtr.Zero) return;
        var sharedApp = ObjCRet(nsAppClass, sel_registerName("sharedApplication"));
        if (sharedApp == IntPtr.Zero) return;
        var nsWindows = ObjCRet(sharedApp, sel_registerName("windows"));
        if (nsWindows == IntPtr.Zero) return;

        var count = (int)ObjCRet(nsWindows, sel_registerName("count"));
        for (int i = 0; i < count; i++)
        {
            var nsWindow = ObjCRetArg(nsWindows, sel_registerName("objectAtIndex:"), (IntPtr)i);
            var mask = (ulong)ObjCRet(nsWindow, sel_registerName("styleMask"));
            // NSWindowStyleMask: Titled=1, Closable=2, Miniaturizable=4, Resizable=8
            // 移除 Resizable 禁用最大化按钮
            ObjCVoid(nsWindow, sel_registerName("setStyleMask:"), (IntPtr)(mask & ~8UL));
        }
    }

    public static void ResizeWindow(double height)
    {
        var nsWindow = GetFirstNSWindow();
        if (nsWindow != IntPtr.Zero)
        {
            ObjCVoidDoubles(nsWindow, sel_registerName("setContentSize:"), ConfigService.ExpandedWidth, height - MacTitleBarHeight);
        }
        if (MainWindow != null)
            MainWindow.Height = height - MacTitleBarHeight;
    }

    private static IntPtr GetFirstNSWindow()
    {
        var nsAppClass = objc_getClass("NSApplication");
        if (nsAppClass == IntPtr.Zero) return IntPtr.Zero;
        var sharedApp = ObjCRet(nsAppClass, sel_registerName("sharedApplication"));
        if (sharedApp == IntPtr.Zero) return IntPtr.Zero;
        var nsWindows = ObjCRet(sharedApp, sel_registerName("windows"));
        if (nsWindows == IntPtr.Zero) return IntPtr.Zero;

        var count = (int)ObjCRet(nsWindows, sel_registerName("count"));
        if (count == 0) return IntPtr.Zero;
        return ObjCRetArg(nsWindows, sel_registerName("objectAtIndex:"), (IntPtr)0);
    }
#endif
}
