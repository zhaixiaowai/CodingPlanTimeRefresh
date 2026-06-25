using AppKit;
using Foundation;
using Microsoft.Maui.Controls;
using Microsoft.Maui.Platform;
using UIKit;

namespace CodingPlanTimeRefresh.Platforms.MacCatalyst
{
    public static class MacWindowHelper
    {
        /// <summary>
        /// 设置窗口置顶
        /// </summary>
        public static void SetAlwaysOnTop(Window? mauiWindow, bool alwaysOnTop)
        {
            var scene = UIApplication.SharedApplication
                .ConnectedScenes
                .OfType<UIWindowScene>()
                .FirstOrDefault();

            var window = scene?
                .Windows
                .FirstOrDefault(w => w.IsKeyWindow);

            if (window?.WindowScene?.Titlebar?.TitleVisibility != null)
            {
                window.WindowLevel = alwaysOnTop ? UIWindowLevel.Alert :    UIWindowLevel.Normal;            
            }
        }
    }
}
