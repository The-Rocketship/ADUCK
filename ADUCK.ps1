<#
.SYNOPSIS
    Modern Active Directory Users and Computers (ADUCK)
    A modern, WinForms/GUI-based replacement for the classic Active Directory Users and Computers (ADUC / dsa.msc)
    MMC snap-in with default Dark Mode, live AD support, and an interactive simulated demo mode.

.DESCRIPTION
    ADUCK provides a fast, streamlined, dark-themed administrative console for managing Active Directory:
    - Default Dark Mode with Windows 10/11/Server native dark title bar integration (DWM).
    - Hierarchical Directory Tree (Domains, Builtin Containers, Organizational Units).
    - Rich Object List with instant search, type filtering, column sorting, and custom glyph icons.
    - Quick Inspector Drawer for rapid triage of users, groups, and computers without opening dialogs.
    - Context actions: Reset Password, Enable/Disable, Unlock Account, Move Object, Delete, Add to Group.
    - Full-featured Tabbed Properties Dialog (General, Account, Member Of, Organization, Attributes).
    - Object Creation Wizards (New User, New Group, New Computer, New OU).
    - Automatic Dual-Engine: Seamlessly connects to real Active Directory domains (via AD module or ADSI)
      or launches into a rich interactive simulated enterprise directory (CORP.CONTOSO.LOCAL) when offline or
      when running with -Demo.

.PARAMETER Domain
    The target Active Directory domain name (e.g. contoso.com).

.PARAMETER Server
    The target Domain Controller (e.g. dc01.contoso.com).

.PARAMETER Credential
    Optional PSCredential to connect to the directory.

.PARAMETER Demo
    Forces ADUCK to launch in interactive simulated demo mode with sample enterprise data.

.PARAMETER LightMode
    Launches in classic light mode instead of the default dark mode.

.EXAMPLE
    .\ADUCK.ps1
    Launches ADUCK (auto-detects AD; falls back to Demo mode if not domain joined).

.EXAMPLE
    .\ADUCK.ps1 -Demo
    Launches interactive demo mode directly.

.EXAMPLE
    .\ADUCK.ps1 -Domain "corp.contoso.com" -Server "dc01.corp.contoso.com"
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Domain,

    [Parameter(Position = 1)]
    [string]$Server,

    [System.Management.Automation.PSCredential]$Credential,

    [switch]$Demo,

    [switch]$LightMode
)

# Set Strict Mode & Error Handling
Set-StrictMode -Off
$ErrorActionPreference = 'Stop'

# Load required assemblies
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
try { Add-Type -AssemblyName System.DirectoryServices -ErrorAction SilentlyContinue } catch {}

# -----------------------------------------------------------------------------
# C# Helper Types: Dark ToolStrip Renderer, ListView Sorter, Win32 Dark Title Bar
# -----------------------------------------------------------------------------
$csharpCode = @'
using System;
using System.Collections;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;
using System.Runtime.InteropServices;

namespace ADUCK {
    public class DarkColorTable : ProfessionalColorTable {
        private Color _bg = Color.FromArgb(24, 25, 38);
        private Color _surface = Color.FromArgb(30, 32, 48);
        private Color _hover = Color.FromArgb(46, 52, 78);
        private Color _border = Color.FromArgb(58, 64, 94);
        private Color _accent = Color.FromArgb(56, 189, 248);

        public void SetPalette(Color bg, Color surface, Color hover, Color border, Color accent) {
            _bg = bg;
            _surface = surface;
            _hover = hover;
            _border = border;
            _accent = accent;
        }

        public override Color MenuStripGradientBegin { get { return _bg; } }
        public override Color MenuStripGradientEnd { get { return _bg; } }
        public override Color ToolStripDropDownBackground { get { return _surface; } }
        public override Color ImageMarginGradientBegin { get { return _surface; } }
        public override Color ImageMarginGradientMiddle { get { return _surface; } }
        public override Color ImageMarginGradientEnd { get { return _surface; } }
        public override Color MenuItemSelected { get { return _hover; } }
        public override Color MenuItemSelectedGradientBegin { get { return _hover; } }
        public override Color MenuItemSelectedGradientEnd { get { return _hover; } }
        public override Color MenuBorder { get { return _border; } }
        public override Color MenuItemBorder { get { return _accent; } }
        public override Color SeparatorDark { get { return _border; } }
        public override Color SeparatorLight { get { return Color.Transparent; } }
        public override Color StatusStripGradientBegin { get { return _bg; } }
        public override Color StatusStripGradientEnd { get { return _bg; } }
        public override Color ButtonSelectedHighlight { get { return _hover; } }
        public override Color ButtonSelectedGradientBegin { get { return _hover; } }
        public override Color ButtonSelectedGradientMiddle { get { return _hover; } }
        public override Color ButtonSelectedGradientEnd { get { return _hover; } }
        public override Color ButtonPressedGradientBegin { get { return _surface; } }
        public override Color ButtonPressedGradientMiddle { get { return _surface; } }
        public override Color ButtonPressedGradientEnd { get { return _surface; } }
    }

    public class DarkToolStripRenderer : ToolStripProfessionalRenderer {
        private Color _textColor = Color.FromArgb(226, 232, 240);

        public DarkToolStripRenderer(DarkColorTable table) : base(table) {
            this.RoundedEdges = true;
        }

        public void SetTextColor(Color text) {
            _textColor = text;
        }

        protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e) {
            e.TextColor = e.Item.Enabled ? _textColor : Color.FromArgb(120, 125, 145);
            base.OnRenderItemText(e);
        }

        protected override void OnRenderArrow(ToolStripArrowRenderEventArgs e) {
            e.ArrowColor = _textColor;
            base.OnRenderArrow(e);
        }
    }

    public class DarkButton : Button {
        public Color NormalBackColor { get; set; }
        public Color NormalForeColor { get; set; }
        public Color NormalBorderColor { get; set; }

        public Color HoverBackColor { get; set; }
        public Color HoverForeColor { get; set; }
        public Color HoverBorderColor { get; set; }

        public Color PressedBackColor { get; set; }

        public Color DisabledBackColor { get; set; }
        public Color DisabledForeColor { get; set; }
        public Color DisabledBorderColor { get; set; }

        public int CornerRadius { get; set; }

        private bool _isHovered;
        private bool _isPressed;

        public override Color BackColor {
            get { return NormalBackColor; }
            set { NormalBackColor = value; base.BackColor = value; Invalidate(); }
        }

        public override Color ForeColor {
            get { return NormalForeColor; }
            set { NormalForeColor = value; base.ForeColor = value; Invalidate(); }
        }

        public DarkButton() {
            NormalBackColor = Color.FromArgb(40, 44, 68);
            NormalForeColor = Color.FromArgb(238, 242, 255);
            NormalBorderColor = Color.FromArgb(68, 75, 110);

            HoverBackColor = Color.FromArgb(54, 60, 92);
            HoverForeColor = Color.FromArgb(255, 255, 255);
            HoverBorderColor = Color.FromArgb(56, 189, 248);

            PressedBackColor = Color.FromArgb(30, 34, 52);

            DisabledBackColor = Color.FromArgb(28, 31, 48);
            DisabledForeColor = Color.FromArgb(165, 175, 205);
            DisabledBorderColor = Color.FromArgb(52, 58, 86);

            CornerRadius = 4;
            _isHovered = false;
            _isPressed = false;

            SetStyle(ControlStyles.UserPaint |
                     ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer |
                     ControlStyles.ResizeRedraw |
                     ControlStyles.SupportsTransparentBackColor, true);
            FlatStyle = FlatStyle.Flat;
            FlatAppearance.BorderSize = 0;
            Cursor = Cursors.Hand;
        }

        public void SetPalette(Color normalBg, Color normalFg, Color normalBorder,
                               Color hoverBg, Color hoverFg, Color hoverBorder,
                               Color disabledBg, Color disabledFg, Color disabledBorder) {
            NormalBackColor = normalBg;
            NormalForeColor = normalFg;
            NormalBorderColor = normalBorder;
            HoverBackColor = hoverBg;
            HoverForeColor = hoverFg;
            HoverBorderColor = hoverBorder;
            DisabledBackColor = disabledBg;
            DisabledForeColor = disabledFg;
            DisabledBorderColor = disabledBorder;
            base.BackColor = normalBg;
            base.ForeColor = normalFg;
            Invalidate();
        }

        protected override void OnMouseEnter(EventArgs e) {
            _isHovered = true;
            base.OnMouseEnter(e);
            Invalidate();
        }

        protected override void OnMouseLeave(EventArgs e) {
            _isHovered = false;
            _isPressed = false;
            base.OnMouseLeave(e);
            Invalidate();
        }

        protected override void OnMouseDown(MouseEventArgs e) {
            if (e.Button == MouseButtons.Left) {
                _isPressed = true;
                Invalidate();
            }
            base.OnMouseDown(e);
        }

        protected override void OnMouseUp(MouseEventArgs e) {
            _isPressed = false;
            base.OnMouseUp(e);
            Invalidate();
        }

        protected override void OnEnabledChanged(EventArgs e) {
            base.OnEnabledChanged(e);
            Invalidate();
        }

        private GraphicsPath GetRoundedPath(Rectangle rect, int radius) {
            GraphicsPath path = new GraphicsPath();
            if (radius <= 0) {
                path.AddRectangle(rect);
                return path;
            }
            int d = radius * 2;
            path.AddArc(rect.X, rect.Y, d, d, 180, 90);
            path.AddArc(rect.Right - d, rect.Y, d, d, 270, 90);
            path.AddArc(rect.Right - d, rect.Bottom - d, d, d, 0, 90);
            path.AddArc(rect.X, rect.Bottom - d, d, d, 90, 90);
            path.CloseFigure();
            return path;
        }

        protected override void OnPaint(PaintEventArgs pevent) {
            Graphics g = pevent.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;

            Color parentBg = Color.Transparent;
            Control p = Parent;
            while (p != null && (parentBg == Color.Transparent || parentBg.A == 0)) {
                parentBg = p.BackColor;
                p = p.Parent;
            }
            if (parentBg == Color.Transparent || parentBg.A == 0) {
                parentBg = Color.FromArgb(33, 36, 54);
            }
            using (SolidBrush bgBrush = new SolidBrush(parentBg)) {
                g.FillRectangle(bgBrush, ClientRectangle);
            }

            Color bg, fg, border;
            if (!Enabled) {
                bg = DisabledBackColor;
                fg = DisabledForeColor;
                border = DisabledBorderColor;
            } else if (_isPressed) {
                bg = PressedBackColor;
                fg = NormalForeColor;
                border = HoverBorderColor;
            } else if (_isHovered) {
                bg = HoverBackColor;
                fg = HoverForeColor;
                border = HoverBorderColor;
            } else {
                bg = NormalBackColor;
                fg = NormalForeColor;
                border = NormalBorderColor;
            }

            Rectangle btnRect = new Rectangle(0, 0, Width - 1, Height - 1);
            using (GraphicsPath path = GetRoundedPath(btnRect, CornerRadius)) {
                using (SolidBrush fillBrush = new SolidBrush(bg)) {
                    g.FillPath(fillBrush, path);
                }
                if (border != Color.Transparent) {
                    using (Pen pen = new Pen(border, 1f)) {
                        g.DrawPath(pen, path);
                    }
                }
            }

            TextRenderer.DrawText(g, this.Text, this.Font, ClientRectangle, fg,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine | TextFormatFlags.EndEllipsis);
        }
    }

    public class ListViewColumnSorter : IComparer {
        public int ColumnIndex { get; set; }
        public SortOrder Order { get; set; }

        public ListViewColumnSorter() {
            ColumnIndex = 0;
            Order = SortOrder.Ascending;
        }

        public int Compare(object x, object y) {
            ListViewItem itemX = x as ListViewItem;
            ListViewItem itemY = y as ListViewItem;
            if (itemX == null || itemY == null) return 0;

            string textX = itemX.SubItems.Count > ColumnIndex ? itemX.SubItems[ColumnIndex].Text : "";
            string textY = itemY.SubItems.Count > ColumnIndex ? itemY.SubItems[ColumnIndex].Text : "";

            int result = String.Compare(textX, textY, StringComparison.CurrentCultureIgnoreCase);
            if (Order == SortOrder.Descending) {
                result = -result;
            }
            return result;
        }
    }

    public class NativeMethods {
        [DllImport("dwmapi.dll", PreserveSig = true)]
        public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);

        public static void ApplyDarkTitleBar(IntPtr handle, bool enable) {
            try {
                int darkMode = enable ? 1 : 0;
                // DWMWA_USE_IMMERSIVE_DARK_MODE (attribute 20 on Win 10 2004+ / Win 11; attribute 19 on older Win 10)
                int hr = DwmSetWindowAttribute(handle, 20, ref darkMode, sizeof(int));
                if (hr != 0) {
                    DwmSetWindowAttribute(handle, 19, ref darkMode, sizeof(int));
                }
            } catch {}
        }
    }
}
'@

if (-not ([System.Management.Automation.PSTypeName]'ADUCK.DarkColorTable').Type) {
    Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition $csharpCode
}

# -----------------------------------------------------------------------------
# Color Palettes & Theme System
# -----------------------------------------------------------------------------
$Script:ThemeDark = @{
    Name            = 'Dark'
    Background      = [System.Drawing.Color]::FromArgb(18, 20, 29)      # Deep Slate / Dark Navy
    Surface         = [System.Drawing.Color]::FromArgb(26, 28, 42)      # Cards, ListView, TreeView
    SurfaceAlt      = [System.Drawing.Color]::FromArgb(33, 36, 54)      # Elevated panels, hover
    HeaderBg        = [System.Drawing.Color]::FromArgb(14, 15, 24)      # Top title banner
    Border          = [System.Drawing.Color]::FromArgb(48, 52, 78)      # Dividers & Card borders
    BorderLight     = [System.Drawing.Color]::FromArgb(65, 70, 102)
    TextPrimary     = [System.Drawing.Color]::FromArgb(238, 242, 255)   # Crisp high-contrast white
    TextSecondary   = [System.Drawing.Color]::FromArgb(156, 163, 195)   # Muted descriptions
    TextMuted       = [System.Drawing.Color]::FromArgb(105, 112, 140)
    Accent          = [System.Drawing.Color]::FromArgb(56, 189, 248)    # Sky blue accent
    AccentHover     = [System.Drawing.Color]::FromArgb(14, 165, 233)
    AccentDark      = [System.Drawing.Color]::FromArgb(2, 132, 199)
    InputBg         = [System.Drawing.Color]::FromArgb(35, 38, 58)
    InputBorder     = [System.Drawing.Color]::FromArgb(55, 60, 90)
    Success         = [System.Drawing.Color]::FromArgb(34, 197, 94)     # Emerald Green
    SuccessBg       = [System.Drawing.Color]::FromArgb(20, 48, 35)
    Warning         = [System.Drawing.Color]::FromArgb(245, 158, 11)    # Amber
    WarningBg       = [System.Drawing.Color]::FromArgb(52, 38, 14)
    Danger          = [System.Drawing.Color]::FromArgb(239, 68, 68)     # Coral Red
    DangerBg        = [System.Drawing.Color]::FromArgb(52, 20, 24)
    ChipBg          = [System.Drawing.Color]::FromArgb(38, 42, 64)
    BtnBg           = [System.Drawing.Color]::FromArgb(40, 44, 68)      # Elevated button surface
    BtnBorder       = [System.Drawing.Color]::FromArgb(68, 75, 110)     # Crisp visible button border
    BtnHoverBg      = [System.Drawing.Color]::FromArgb(54, 60, 92)      # High-visibility hover
    BtnHoverBorder  = [System.Drawing.Color]::FromArgb(56, 189, 248)    # Accent border on hover
    BtnDisabledBg   = [System.Drawing.Color]::FromArgb(28, 31, 48)      # Recessed disabled surface
    BtnDisabledFg   = [System.Drawing.Color]::FromArgb(165, 175, 205)   # High-contrast readable muted text
    BtnDisabledBorder = [System.Drawing.Color]::FromArgb(52, 58, 86)    # Clearly delineated disabled border
}

$Script:ThemeLight = @{
    Name            = 'Light'
    Background      = [System.Drawing.Color]::FromArgb(241, 245, 249)   # Slate-100
    Surface         = [System.Drawing.Color]::FromArgb(255, 255, 255)   # Pure White
    SurfaceAlt      = [System.Drawing.Color]::FromArgb(241, 245, 249)   # Slate-100 (elevated panels & drawer)
    HeaderBg        = [System.Drawing.Color]::FromArgb(255, 255, 255)   # Crisp white header
    Border          = [System.Drawing.Color]::FromArgb(203, 213, 225)   # Slate-300
    BorderLight     = [System.Drawing.Color]::FromArgb(226, 232, 240)   # Slate-200
    TextPrimary     = [System.Drawing.Color]::FromArgb(15, 23, 42)      # Slate-900 (deep charcoal, maximum contrast)
    TextSecondary   = [System.Drawing.Color]::FromArgb(71, 85, 105)     # Slate-600 (very clear secondary text)
    TextMuted       = [System.Drawing.Color]::FromArgb(148, 163, 184)   # Slate-400
    Accent          = [System.Drawing.Color]::FromArgb(2, 132, 199)     # Sky-600
    AccentHover     = [System.Drawing.Color]::FromArgb(3, 105, 161)     # Sky-700
    AccentDark      = [System.Drawing.Color]::FromArgb(14, 116, 144)    # Cyan-700
    InputBg         = [System.Drawing.Color]::FromArgb(255, 255, 255)   # White
    InputBorder     = [System.Drawing.Color]::FromArgb(203, 213, 225)   # Slate-300
    Success         = [System.Drawing.Color]::FromArgb(21, 128, 61)     # Green-700 (dark crisp green)
    SuccessBg       = [System.Drawing.Color]::FromArgb(220, 252, 231)   # Green-100
    Warning         = [System.Drawing.Color]::FromArgb(146, 64, 14)     # Amber-800 (dark crisp amber)
    WarningBg       = [System.Drawing.Color]::FromArgb(254, 243, 199)   # Amber-100
    Danger          = [System.Drawing.Color]::FromArgb(185, 28, 28)     # Red-700
    DangerBg        = [System.Drawing.Color]::FromArgb(254, 226, 226)   # Red-100
    ChipBg          = [System.Drawing.Color]::FromArgb(226, 232, 240)   # Slate-200
    BtnBg           = [System.Drawing.Color]::FromArgb(255, 255, 255)   # Clean white button
    BtnBorder       = [System.Drawing.Color]::FromArgb(203, 213, 225)   # Slate-300
    BtnHoverBg      = [System.Drawing.Color]::FromArgb(241, 245, 249)   # Slate-100
    BtnHoverBorder  = [System.Drawing.Color]::FromArgb(2, 132, 199)     # Sky-600
    BtnDisabledBg   = [System.Drawing.Color]::FromArgb(248, 250, 252)   # Slate-50
    BtnDisabledFg   = [System.Drawing.Color]::FromArgb(148, 163, 184)   # Slate-400
    BtnDisabledBorder = [System.Drawing.Color]::FromArgb(226, 232, 240) # Slate-200
}

$Script:Theme = if ($LightMode) { $Script:ThemeLight } else { $Script:ThemeDark }

# Initialize Custom Renderer
$Script:ColorTable = New-Object ADUCK.DarkColorTable
$Script:ColorTable.SetPalette($Script:Theme.HeaderBg, $Script:Theme.Surface, $Script:Theme.SurfaceAlt, $Script:Theme.Border, $Script:Theme.Accent)
$Script:ToolStripRenderer = New-Object ADUCK.DarkToolStripRenderer($Script:ColorTable)
$Script:ToolStripRenderer.SetTextColor($Script:Theme.TextPrimary)

# Standard Fonts
$Script:FontFamily = "Segoe UI"
$Script:FontLargeTitle = New-Object System.Drawing.Font($Script:FontFamily, 13, [System.Drawing.FontStyle]::Bold)
$Script:FontTitle      = New-Object System.Drawing.Font($Script:FontFamily, 11, [System.Drawing.FontStyle]::Bold)
$Script:FontSubtitle   = New-Object System.Drawing.Font($Script:FontFamily, 9, [System.Drawing.FontStyle]::Regular)
$Script:FontBodyBold   = New-Object System.Drawing.Font($Script:FontFamily, 9.5, [System.Drawing.FontStyle]::Bold)
$Script:FontBody       = New-Object System.Drawing.Font($Script:FontFamily, 9.5, [System.Drawing.FontStyle]::Regular)
$Script:FontSmall      = New-Object System.Drawing.Font($Script:FontFamily, 8.5, [System.Drawing.FontStyle]::Regular)
$Script:FontSmallBold  = New-Object System.Drawing.Font($Script:FontFamily, 8.5, [System.Drawing.FontStyle]::Bold)
$Script:FontCode       = New-Object System.Drawing.Font("Consolas", 9, [System.Drawing.FontStyle]::Regular)

# -----------------------------------------------------------------------------
# Vector Icon Factory & Duck Mascot
# -----------------------------------------------------------------------------
function New-DuckBitmap {
    param([int]$Size = 32)

    $bmp = New-Object System.Drawing.Bitmap($Size, $Size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)

    $scale = $Size / 32.0

    $duckYellow     = [System.Drawing.Color]::FromArgb(254, 224, 60)
    $duckYellowDark = [System.Drawing.Color]::FromArgb(234, 179, 8)
    $billOrange     = [System.Drawing.Color]::FromArgb(249, 115, 22)
    $eyeWhite       = [System.Drawing.Color]::White
    $eyeBlack       = [System.Drawing.Color]::FromArgb(20, 20, 20)

    $bodyBrush  = New-Object System.Drawing.SolidBrush($duckYellow)
    $wingBrush  = New-Object System.Drawing.SolidBrush($duckYellowDark)
    $billBrush  = New-Object System.Drawing.SolidBrush($billOrange)
    $whiteBrush = New-Object System.Drawing.SolidBrush($eyeWhite)
    $blackBrush = New-Object System.Drawing.SolidBrush($eyeBlack)

    # 1. Perky Duck Tail
    $tailPath = New-Object System.Drawing.Drawing2D.GraphicsPath
    $tailPts = @(
        [System.Drawing.PointF]::new([float](10 * $scale), [float](16 * $scale)),
        [System.Drawing.PointF]::new([float](2 * $scale), [float](10 * $scale)),
        [System.Drawing.PointF]::new([float](6 * $scale), [float](22 * $scale))
    )
    $tailPath.AddPolygon($tailPts)
    $g.FillPath($bodyBrush, $tailPath)
    $tailPath.Dispose()

    # 2. Body
    $g.FillEllipse($bodyBrush, [float](4 * $scale), [float](13 * $scale), [float](23 * $scale), [float](16 * $scale))

    # 3. Head
    $g.FillEllipse($bodyBrush, [float](15 * $scale), [float](3 * $scale), [float](15 * $scale), [float](15 * $scale))

    # 4. Beak / Bill
    $billPath = New-Object System.Drawing.Drawing2D.GraphicsPath
    $billPts = @(
        [System.Drawing.PointF]::new([float](26 * $scale), [float](9 * $scale)),
        [System.Drawing.PointF]::new([float](32 * $scale), [float](11.5 * $scale)),
        [System.Drawing.PointF]::new([float](26 * $scale), [float](14 * $scale))
    )
    $billPath.AddPolygon($billPts)
    $g.FillPath($billBrush, $billPath)
    $billPath.Dispose()

    # 5. Wing
    $g.FillEllipse($wingBrush, [float](8 * $scale), [float](16 * $scale), [float](11 * $scale), [float](8 * $scale))

    # 6. Eye & Reflection
    $g.FillEllipse($blackBrush, [float](22 * $scale), [float](7 * $scale), [float](3 * $scale), [float](3.5 * $scale))
    $g.FillEllipse($whiteBrush, [float](23 * $scale), [float](7.5 * $scale), [float](1.2 * $scale), [float](1.2 * $scale))

    $bodyBrush.Dispose(); $wingBrush.Dispose(); $billBrush.Dispose()
    $whiteBrush.Dispose(); $blackBrush.Dispose(); $g.Dispose()

    return $bmp
}

function New-CustomIcon {
    param(
        [Parameter(Mandatory=$true)][string]$IconType,
        [int]$Size = 16
    )

    $bmp = New-Object System.Drawing.Bitmap($Size, $Size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)

    $scale = $Size / 16.0

    switch ($IconType) {
        'domain' {
            # Globe with latitude / longitude lines
            $pen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(56, 189, 248), [float](1.6 * $scale))
            $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(28, 64, 94))
            $g.FillEllipse($brush, 2 * $scale, 2 * $scale, 12 * $scale, 12 * $scale)
            $g.DrawEllipse($pen, 2 * $scale, 2 * $scale, 12 * $scale, 12 * $scale)
            $g.DrawLine($pen, 2 * $scale, 8 * $scale, 14 * $scale, 8 * $scale)
            $g.DrawEllipse($pen, 5 * $scale, 2 * $scale, 6 * $scale, 12 * $scale)
            $brush.Dispose(); $pen.Dispose()
        }
        'ou' {
            # Modern Golden Folder with hierarchy node
            $folderBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(234, 179, 8))
            $tabBrush    = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(202, 138, 4))
            $g.FillRectangle($tabBrush, 2 * $scale, 2 * $scale, 6 * $scale, 3 * $scale)
            $g.FillRectangle($folderBrush, 2 * $scale, 4 * $scale, 12 * $scale, 10 * $scale)
            # Small node badge
            $badgeBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(254, 240, 138))
            $g.FillEllipse($badgeBrush, 7 * $scale, 8 * $scale, 3 * $scale, 3 * $scale)
            $folderBrush.Dispose(); $tabBrush.Dispose(); $badgeBrush.Dispose()
        }
        'container' {
            # Light Slate Container Folder
            $folderBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(148, 163, 184))
            $tabBrush    = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(100, 116, 139))
            $g.FillRectangle($tabBrush, 2 * $scale, 2 * $scale, 5 * $scale, 3 * $scale)
            $g.FillRectangle($folderBrush, 2 * $scale, 4 * $scale, 12 * $scale, 10 * $scale)
            $folderBrush.Dispose(); $tabBrush.Dispose()
        }
        'user_active' {
            # Blue User Silhouette
            $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(56, 189, 248))
            # Head
            $g.FillEllipse($brush, 5.5 * $scale, 1.5 * $scale, 5 * $scale, 5 * $scale)
            # Torso
            $path = New-Object System.Drawing.Drawing2D.GraphicsPath
            $path.AddArc(2.5 * $scale, 7.5 * $scale, 11 * $scale, 9 * $scale, 180, 180)
            $g.FillPath($brush, $path)
            $path.Dispose(); $brush.Dispose()
        }
        'user_disabled' {
            # Muted User with Red Slash
            $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(105, 112, 140))
            $g.FillEllipse($brush, 5.5 * $scale, 1.5 * $scale, 5 * $scale, 5 * $scale)
            $path = New-Object System.Drawing.Drawing2D.GraphicsPath
            $path.AddArc(2.5 * $scale, 7.5 * $scale, 11 * $scale, 9 * $scale, 180, 180)
            $g.FillPath($brush, $path)
            $path.Dispose(); $brush.Dispose()
            # Red Slash
            $redPen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(239, 68, 68), [float](2.2 * $scale))
            $g.DrawLine($redPen, 3 * $scale, 13 * $scale, 13 * $scale, 3 * $scale)
            $redPen.Dispose()
        }
        'user_locked' {
            # User with Amber Padlock Badge
            $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(148, 163, 184))
            $g.FillEllipse($brush, 4.5 * $scale, 1.5 * $scale, 5 * $scale, 5 * $scale)
            $path = New-Object System.Drawing.Drawing2D.GraphicsPath
            $path.AddArc(1.5 * $scale, 7.5 * $scale, 11 * $scale, 9 * $scale, 180, 180)
            $g.FillPath($brush, $path)
            $path.Dispose(); $brush.Dispose()
            # Lock Body
            $lockBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(245, 158, 11))
            $g.FillRectangle($lockBrush, 9 * $scale, 9 * $scale, 6 * $scale, 6 * $scale)
            # Lock Shackle
            $lockPen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(245, 158, 11), [float](1.5 * $scale))
            $g.DrawArc($lockPen, 10 * $scale, 6 * $scale, 4 * $scale, 5 * $scale, 180, 180)
            $lockBrush.Dispose(); $lockPen.Dispose()
        }
        'group' {
            # Dual user silhouette (Security Group)
            $brushBack  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(129, 140, 248))
            $brushFront = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(168, 85, 247))
            # Back User
            $g.FillEllipse($brushBack, 7.5 * $scale, 1 * $scale, 4.5 * $scale, 4.5 * $scale)
            $pathBack = New-Object System.Drawing.Drawing2D.GraphicsPath
            $pathBack.AddArc(5 * $scale, 6.5 * $scale, 9.5 * $scale, 7.5 * $scale, 180, 180)
            $g.FillPath($brushBack, $pathBack)
            $pathBack.Dispose()
            # Front User
            $g.FillEllipse($brushFront, 3 * $scale, 3 * $scale, 4.5 * $scale, 4.5 * $scale)
            $pathFront = New-Object System.Drawing.Drawing2D.GraphicsPath
            $pathFront.AddArc(0.5 * $scale, 8.5 * $scale, 9.5 * $scale, 7.5 * $scale, 180, 180)
            $g.FillPath($brushFront, $pathFront)
            $pathFront.Dispose(); $brushBack.Dispose(); $brushFront.Dispose()
        }
        'computer' {
            # Modern Desktop / Server Monitor
            $tealBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(45, 212, 191))
            $baseBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(20, 184, 166))
            # Screen
            $g.FillRectangle($tealBrush, 2 * $scale, 2 * $scale, 12 * $scale, 9 * $scale)
            $screenInner = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(19, 78, 74))
            $g.FillRectangle($screenInner, 3.5 * $scale, 3.5 * $scale, 9 * $scale, 6 * $scale)
            # Stand
            $g.FillRectangle($baseBrush, 7 * $scale, 11 * $scale, 2 * $scale, 2 * $scale)
            $g.FillRectangle($baseBrush, 4 * $scale, 13 * $scale, 8 * $scale, 1.5 * $scale)
            $tealBrush.Dispose(); $baseBrush.Dispose(); $screenInner.Dispose()
        }
        'refresh' {
            $pen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(56, 189, 248), [float](2 * $scale))
            $g.DrawArc($pen, 2 * $scale, 2 * $scale, 12 * $scale, 12 * $scale, 45, 270)
            $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(56, 189, 248))
            $poly = @(
                [System.Drawing.PointF]::new([float](11 * $scale), [float](2 * $scale)),
                [System.Drawing.PointF]::new([float](14.5 * $scale), [float](4.5 * $scale)),
                [System.Drawing.PointF]::new([float](10 * $scale), [float](6 * $scale))
            )
            $g.FillPolygon($brush, $poly)
            $pen.Dispose(); $brush.Dispose()
        }
        'key' {
            $pen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(251, 191, 36), [float](1.8 * $scale))
            $g.DrawEllipse($pen, 2.5 * $scale, 2.5 * $scale, 6 * $scale, 6 * $scale)
            $g.DrawLine($pen, 7 * $scale, 7 * $scale, 13.5 * $scale, 13.5 * $scale)
            $g.DrawLine($pen, 11 * $scale, 11 * $scale, 13 * $scale, 9 * $scale)
            $g.DrawLine($pen, 12.5 * $scale, 12.5 * $scale, 14.5 * $scale, 10.5 * $scale)
            $pen.Dispose()
        }
        'search' {
            $pen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(148, 163, 184), [float](2 * $scale))
            $g.DrawEllipse($pen, 2.5 * $scale, 2.5 * $scale, 7 * $scale, 7 * $scale)
            $g.DrawLine($pen, 8.5 * $scale, 8.5 * $scale, 13.5 * $scale, 13.5 * $scale)
            $pen.Dispose()
        }
        'properties' {
            $pen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(56, 189, 248), [float](1.8 * $scale))
            $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(56, 189, 248))
            # Sliders
            $g.DrawLine($pen, 2 * $scale, 4 * $scale, 14 * $scale, 4 * $scale)
            $g.FillRectangle($brush, 5 * $scale, 2.5 * $scale, 2.5 * $scale, 3 * $scale)
            $g.DrawLine($pen, 2 * $scale, 8 * $scale, 14 * $scale, 8 * $scale)
            $g.FillRectangle($brush, 9 * $scale, 6.5 * $scale, 2.5 * $scale, 3 * $scale)
            $g.DrawLine($pen, 2 * $scale, 12 * $scale, 14 * $scale, 12 * $scale)
            $g.FillRectangle($brush, 4 * $scale, 10.5 * $scale, 2.5 * $scale, 3 * $scale)
            $pen.Dispose(); $brush.Dispose()
        }
        'plus' {
            $pen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(34, 197, 94), [float](2.4 * $scale))
            $g.DrawLine($pen, 8 * $scale, 2.5 * $scale, 8 * $scale, 13.5 * $scale)
            $g.DrawLine($pen, 2.5 * $scale, 8 * $scale, 13.5 * $scale, 8 * $scale)
            $pen.Dispose()
        }
        'move' {
            $pen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(168, 85, 247), [float](1.8 * $scale))
            $g.DrawLine($pen, 2 * $scale, 8 * $scale, 13 * $scale, 8 * $scale)
            $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(168, 85, 247))
            $poly = @(
                [System.Drawing.PointF]::new([float](10 * $scale), [float](4.5 * $scale)),
                [System.Drawing.PointF]::new([float](14 * $scale), [float](8 * $scale)),
                [System.Drawing.PointF]::new([float](10 * $scale), [float](11.5 * $scale))
            )
            $g.FillPolygon($brush, $poly)
            $pen.Dispose(); $brush.Dispose()
        }
        'delete' {
            $pen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(239, 68, 68), [float](2.2 * $scale))
            $g.DrawLine($pen, 3.5 * $scale, 3.5 * $scale, 12.5 * $scale, 12.5 * $scale)
            $g.DrawLine($pen, 12.5 * $scale, 3.5 * $scale, 3.5 * $scale, 12.5 * $scale)
            $pen.Dispose()
        }
        'duck' {
            $duckBmp = New-DuckBitmap -Size $Size
            $g.DrawImage($duckBmp, 0, 0)
            $duckBmp.Dispose()
        }
        default {
            $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(148, 163, 184))
            $g.FillRectangle($brush, 3 * $scale, 3 * $scale, 10 * $scale, 10 * $scale)
            $brush.Dispose()
        }
    }

    $g.Dispose()
    return $bmp
}

# Pre-generate ImageList for TreeView & ListView
$Script:ImageList = New-Object System.Windows.Forms.ImageList
$Script:ImageList.ImageSize = New-Object System.Drawing.Size(16, 16)
$Script:ImageList.ColorDepth = [System.Windows.Forms.ColorDepth]::Depth32Bit

$iconTypes = @('domain', 'ou', 'container', 'user_active', 'user_disabled', 'user_locked', 'group', 'computer', 'refresh', 'key', 'search', 'properties', 'plus', 'move', 'delete', 'duck')
foreach ($type in $iconTypes) {
    $img = New-CustomIcon -IconType $type -Size 16
    $Script:ImageList.Images.Add($type, $img)
}

# Duck Mascot Assets
$Script:DuckBitmap = New-DuckBitmap -Size 40
$Script:DuckIcon = [System.Drawing.Icon]::FromHandle((New-DuckBitmap -Size 32).GetHicon())

# -----------------------------------------------------------------------------
# Data Layer & Directory Provider Engine (Dual Mode: Live AD & Interactive Demo)
# -----------------------------------------------------------------------------
$Script:IsLiveAD = $false
$Script:ActiveDomainName = ""
$Script:ActiveDCName = ""

# Test for Live Active Directory connection
if (-not $Demo) {
    try {
        if (Get-Module -ListAvailable ActiveDirectory) {
            Import-Module ActiveDirectory -ErrorAction Stop
            $adDomain = if ($Domain) { Get-ADDomain -Identity $Domain -ErrorAction Stop } else { Get-ADDomain -ErrorAction Stop }
            if ($adDomain) {
                $Script:IsLiveAD = $true
                $Script:ActiveDomainName = $adDomain.DNSRoot
                $Script:ActiveDCName = if ($Server) { $Server } else { $adDomain.PDCEmulator }
            }
        }
    } catch {
        $Script:IsLiveAD = $false
    }
}

# In-Memory Simulated Directory Database for Demo Mode
$Script:DemoStore = @{
    Domain = @{
        Name               = "CORP.CONTOSO.LOCAL"
        DistinguishedName  = "DC=corp,DC=contoso,DC=local"
        PDCEmulator        = "DC01.corp.contoso.local"
        Forest             = "contoso.local"
        DomainMode         = "Windows2016Domain"
    }
    Containers = @(
        [PSCustomObject]@{ Name = "Builtin"; DistinguishedName = "CN=Builtin,DC=corp,DC=contoso,DC=local"; Type = "container"; ParentDN = "DC=corp,DC=contoso,DC=local" },
        [PSCustomObject]@{ Name = "Computers"; DistinguishedName = "CN=Computers,DC=corp,DC=contoso,DC=local"; Type = "container"; ParentDN = "DC=corp,DC=contoso,DC=local" },
        [PSCustomObject]@{ Name = "Users"; DistinguishedName = "CN=Users,DC=corp,DC=contoso,DC=local"; Type = "container"; ParentDN = "DC=corp,DC=contoso,DC=local" },
        [PSCustomObject]@{ Name = "Corporate"; DistinguishedName = "OU=Corporate,DC=corp,DC=contoso,DC=local"; Type = "ou"; ParentDN = "DC=corp,DC=contoso,DC=local" },
        [PSCustomObject]@{ Name = "Executive"; DistinguishedName = "OU=Executive,OU=Corporate,DC=corp,DC=contoso,DC=local"; Type = "ou"; ParentDN = "OU=Corporate,DC=corp,DC=contoso,DC=local" },
        [PSCustomObject]@{ Name = "Information Technology"; DistinguishedName = "OU=Information Technology,OU=Corporate,DC=corp,DC=contoso,DC=local"; Type = "ou"; ParentDN = "OU=Corporate,DC=corp,DC=contoso,DC=local" },
        [PSCustomObject]@{ Name = "Engineering"; DistinguishedName = "OU=Engineering,OU=Corporate,DC=corp,DC=contoso,DC=local"; Type = "ou"; ParentDN = "OU=Corporate,DC=corp,DC=contoso,DC=local" },
        [PSCustomObject]@{ Name = "Finance"; DistinguishedName = "OU=Finance,OU=Corporate,DC=corp,DC=contoso,DC=local"; Type = "ou"; ParentDN = "OU=Corporate,DC=corp,DC=contoso,DC=local" },
        [PSCustomObject]@{ Name = "Human Resources"; DistinguishedName = "OU=Human Resources,OU=Corporate,DC=corp,DC=contoso,DC=local"; Type = "ou"; ParentDN = "OU=Corporate,DC=corp,DC=contoso,DC=local" },
        [PSCustomObject]@{ Name = "Sales & Marketing"; DistinguishedName = "OU=Sales & Marketing,OU=Corporate,DC=corp,DC=contoso,DC=local"; Type = "ou"; ParentDN = "OU=Corporate,DC=corp,DC=contoso,DC=local" },
        [PSCustomObject]@{ Name = "Branch Offices"; DistinguishedName = "OU=Branch Offices,DC=corp,DC=contoso,DC=local"; Type = "ou"; ParentDN = "DC=corp,DC=contoso,DC=local" },
        [PSCustomObject]@{ Name = "London"; DistinguishedName = "OU=London,OU=Branch Offices,DC=corp,DC=contoso,DC=local"; Type = "ou"; ParentDN = "OU=Branch Offices,DC=corp,DC=contoso,DC=local" },
        [PSCustomObject]@{ Name = "Tokyo"; DistinguishedName = "OU=Tokyo,OU=Branch Offices,DC=corp,DC=contoso,DC=local"; Type = "ou"; ParentDN = "OU=Branch Offices,DC=corp,DC=contoso,DC=local" },
        [PSCustomObject]@{ Name = "Service Accounts"; DistinguishedName = "OU=Service Accounts,DC=corp,DC=contoso,DC=local"; Type = "ou"; ParentDN = "DC=corp,DC=contoso,DC=local" },
        [PSCustomObject]@{ Name = "Disabled Accounts"; DistinguishedName = "OU=Disabled Accounts,DC=corp,DC=contoso,DC=local"; Type = "ou"; ParentDN = "DC=corp,DC=contoso,DC=local" }
    )
    Objects = [System.Collections.ArrayList]@()
}

# Helper to populate realistic demo directory objects
function Initialize-DemoObjects {
    $Script:DemoStore.Objects.Clear()

    # Pre-defined groups
    $groups = @(
        @{ Name="Domain Admins"; DN="CN=Domain Admins,CN=Users,DC=corp,DC=contoso,DC=local"; Parent="CN=Users,DC=corp,DC=contoso,DC=local"; Desc="Designated administrators of the domain"; Scope="Global"; Type="Security" },
        @{ Name="Enterprise Admins"; DN="CN=Enterprise Admins,CN=Users,DC=corp,DC=contoso,DC=local"; Parent="CN=Users,DC=corp,DC=contoso,DC=local"; Desc="Designated administrators of the enterprise"; Scope="Universal"; Type="Security" },
        @{ Name="Remote Desktop Users"; DN="CN=Remote Desktop Users,CN=Builtin,DC=corp,DC=contoso,DC=local"; Parent="CN=Builtin,DC=corp,DC=contoso,DC=local"; Desc="Members in this group are granted the right to logon remotely"; Scope="DomainLocal"; Type="Security" },
        @{ Name="IT-Admins"; DN="CN=IT-Admins,OU=Information Technology,OU=Corporate,DC=corp,DC=contoso,DC=local"; Parent="OU=Information Technology,OU=Corporate,DC=corp,DC=contoso,DC=local"; Desc="Internal IT Infrastructure Team"; Scope="Global"; Type="Security" },
        @{ Name="DevOps-Engineers"; DN="CN=DevOps-Engineers,OU=Engineering,OU=Corporate,DC=corp,DC=contoso,DC=local"; Parent="OU=Engineering,OU=Corporate,DC=corp,DC=contoso,DC=local"; Desc="Production deployment and cloud infrastructure engineers"; Scope="Global"; Type="Security" },
        @{ Name="Finance-Approvers"; DN="CN=Finance-Approvers,OU=Finance,OU=Corporate,DC=corp,DC=contoso,DC=local"; Parent="OU=Finance,OU=Corporate,DC=corp,DC=contoso,DC=local"; Desc="Authorized to approve corporate wire transfers"; Scope="Global"; Type="Security" },
        @{ Name="All-Employees"; DN="CN=All-Employees,OU=Corporate,DC=corp,DC=contoso,DC=local"; Parent="OU=Corporate,DC=corp,DC=contoso,DC=local"; Desc="All corporate staff distribution group"; Scope="Universal"; Type="Distribution" }
    )
    foreach ($g in $groups) {
        $null = $Script:DemoStore.Objects.Add([PSCustomObject]@{
            ObjectClass       = "group"
            Name              = $g.Name
            sAMAccountName    = $g.Name
            DistinguishedName = $g.DN
            ParentDN          = $g.Parent
            Description       = $g.Desc
            GroupScope        = $g.Scope
            GroupType         = $g.Type
            Enabled           = $true
            LockedOut         = $false
            whenCreated       = (Get-Date).AddDays(-180).ToString("yyyy-MM-dd HH:mm:ss")
            whenChanged       = (Get-Date).AddDays(-12).ToString("yyyy-MM-dd HH:mm:ss")
            MemberOf          = @()
        })
    }

    # Pre-defined computers
    $computers = @(
        @{ Name="DC01"; Parent="OU=Corporate,DC=corp,DC=contoso,DC=local"; OS="Windows Server 2022 Datacenter"; Desc="Primary Domain Controller" },
        @{ Name="DC02"; Parent="OU=Corporate,DC=corp,DC=contoso,DC=local"; OS="Windows Server 2022 Datacenter"; Desc="Secondary Domain Controller" },
        @{ Name="FS-CORP-01"; Parent="CN=Computers,DC=corp,DC=contoso,DC=local"; OS="Windows Server 2019 Standard"; Desc="Corporate File Server" },
        @{ Name="SQL-PROD-01"; Parent="CN=Computers,DC=corp,DC=contoso,DC=local"; OS="Windows Server 2022 Datacenter"; Desc="Production SQL Database Cluster" },
        @{ Name="WS-EXEC-01"; Parent="OU=Executive,OU=Corporate,DC=corp,DC=contoso,DC=local"; OS="Windows 11 Enterprise"; Desc="Executive Workstation" },
        @{ Name="WS-IT-004"; Parent="OU=Information Technology,OU=Corporate,DC=corp,DC=contoso,DC=local"; OS="Windows 11 Enterprise"; Desc="IT Lab Workstation" }
    )
    foreach ($c in $computers) {
        $null = $Script:DemoStore.Objects.Add([PSCustomObject]@{
            ObjectClass                = "computer"
            Name                       = $c.Name
            sAMAccountName             = "$($c.Name)$"
            DistinguishedName          = "CN=$($c.Name),$($c.Parent)"
            ParentDN                   = $c.Parent
            Description                = $c.Desc
            OperatingSystem            = $c.OS
            OperatingSystemVersion     = "10.0 (20348)"
            OperatingSystemServicePack  = ""
            DNSHostName                = "$($c.Name.ToLower()).corp.contoso.local"
            Location                   = "Redmond Data Center Rack 4"
            manager                    = "CN=Alex Mercer,OU=Information Technology,OU=Corporate,DC=corp,DC=contoso,DC=local"
            msNPAllowDialin            = $true
            msNPCallingStationID       = ""
            msRADIUSFramedIPAddress    = ""
            Enabled                    = $true
            LockedOut                  = $false
            whenCreated                = (Get-Date).AddDays(-300).ToString("yyyy-MM-dd HH:mm:ss")
            whenChanged                = (Get-Date).AddDays(-5).ToString("yyyy-MM-dd HH:mm:ss")
            MemberOf                   = @("CN=Domain Computers,CN=Users,DC=corp,DC=contoso,DC=local")
            uSNCreated                 = "$((Get-Random -Minimum 100000 -Maximum 999999))"
            uSNChanged                 = "$((Get-Random -Minimum 100000 -Maximum 999999))"
        })
    }

    # Pre-defined users
    $users = @(
        @{ First="Eleanor"; Last="Vance"; SAM="evance"; Parent="OU=Executive,OU=Corporate,DC=corp,DC=contoso,DC=local"; Title="Chief Executive Officer"; Dept="Executive"; Phone="+1 (555) 019-2831"; Enabled=$true; Locked=$false; Groups=@("All-Employees") },
        @{ First="Marcus"; Last="Holloway"; SAM="mholloway"; Parent="OU=Executive,OU=Corporate,DC=corp,DC=contoso,DC=local"; Title="Chief Technology Officer"; Dept="Executive"; Phone="+1 (555) 019-2832"; Enabled=$true; Locked=$false; Groups=@("Domain Admins", "Enterprise Admins", "All-Employees") },
        @{ First="Sofia"; Last="Chen"; SAM="schen"; Parent="OU=Executive,OU=Corporate,DC=corp,DC=contoso,DC=local"; Title="Chief Financial Officer"; Dept="Executive"; Phone="+1 (555) 019-2833"; Enabled=$true; Locked=$false; Groups=@("Finance-Approvers", "All-Employees") },
        @{ First="Alex"; Last="Mercer"; SAM="amercer"; Parent="OU=Information Technology,OU=Corporate,DC=corp,DC=contoso,DC=local"; Title="Lead Systems Administrator"; Dept="Information Technology"; Phone="+1 (555) 014-9821"; Enabled=$true; Locked=$false; Groups=@("Domain Admins", "IT-Admins", "Remote Desktop Users", "All-Employees") },
        @{ First="Jordan"; Last="Lee"; SAM="jlee"; Parent="OU=Information Technology,OU=Corporate,DC=corp,DC=contoso,DC=local"; Title="Senior Cloud Architect"; Dept="Information Technology"; Phone="+1 (555) 014-9822"; Enabled=$true; Locked=$false; Groups=@("IT-Admins", "DevOps-Engineers", "All-Employees") },
        @{ First="Sam"; Last="Taylor"; SAM="staylor"; Parent="OU=Information Technology,OU=Corporate,DC=corp,DC=contoso,DC=local"; Title="Helpdesk Specialist"; Dept="Information Technology"; Phone="+1 (555) 014-9823"; Enabled=$true; Locked=$false; Groups=@("IT-Admins", "All-Employees") },
        @{ First="Lucas"; Last="Scott"; SAM="lscott"; Parent="OU=Engineering,OU=Corporate,DC=corp,DC=contoso,DC=local"; Title="Senior Full-Stack Engineer"; Dept="Engineering"; Phone="+1 (555) 016-4411"; Enabled=$true; Locked=$true; Groups=@("DevOps-Engineers", "All-Employees") },
        @{ First="Elena"; Last="Rostova"; SAM="erostova"; Parent="OU=Engineering,OU=Corporate,DC=corp,DC=contoso,DC=local"; Title="Principal DevOps Engineer"; Dept="Engineering"; Phone="+1 (555) 016-4412"; Enabled=$true; Locked=$false; Groups=@("DevOps-Engineers", "All-Employees") },
        @{ First="David"; Last="Kim"; SAM="dkim"; Parent="OU=Engineering,OU=Corporate,DC=corp,DC=contoso,DC=local"; Title="Software Engineer"; Dept="Engineering"; Phone="+1 (555) 016-4413"; Enabled=$true; Locked=$false; Groups=@("All-Employees") },
        @{ First="Arthur"; Last="Pendelton"; SAM="apendelton"; Parent="OU=Finance,OU=Corporate,DC=corp,DC=contoso,DC=local"; Title="Corporate Controller"; Dept="Finance"; Phone="+1 (555) 017-7721"; Enabled=$true; Locked=$false; Groups=@("Finance-Approvers", "All-Employees") },
        @{ First="Claire"; Last="Dupont"; SAM="cdupont"; Parent="OU=Finance,OU=Corporate,DC=corp,DC=contoso,DC=local"; Title="Senior Auditor"; Dept="Finance"; Phone="+1 (555) 017-7722"; Enabled=$false; Locked=$false; Groups=@("All-Employees") },
        @{ First="Hannah"; Last="Abbott"; SAM="habbott"; Parent="OU=Human Resources,OU=Corporate,DC=corp,DC=contoso,DC=local"; Title="Director of Human Resources"; Dept="Human Resources"; Phone="+1 (555) 018-3341"; Enabled=$true; Locked=$false; Groups=@("All-Employees") },
        @{ First="Ethan"; Last="Hunt"; SAM="ehunt"; Parent="OU=Sales & Marketing,OU=Corporate,DC=corp,DC=contoso,DC=local"; Title="VP of Global Sales"; Dept="Sales & Marketing"; Phone="+1 (555) 012-9901"; Enabled=$true; Locked=$false; Groups=@("All-Employees") },
        @{ First="Sarah"; Last="Miller"; SAM="smiller"; Parent="OU=Sales & Marketing,OU=Corporate,DC=corp,DC=contoso,DC=local"; Title="Senior Enterprise Account Exec"; Dept="Sales & Marketing"; Phone="+1 (555) 012-9902"; Enabled=$true; Locked=$false; Groups=@("All-Employees") },
        @{ First="Oliver"; Last="Twist"; SAM="otwist"; Parent="OU=London,OU=Branch Offices,DC=corp,DC=contoso,DC=local"; Title="UK Regional Director"; Dept="Operations"; Phone="+44 20 7946 0912"; Enabled=$true; Locked=$false; Groups=@("All-Employees") },
        @{ First="Kenji"; Last="Sato"; SAM="ksato"; Parent="OU=Tokyo,OU=Branch Offices,DC=corp,DC=contoso,DC=local"; Title="APAC Systems Lead"; Dept="Information Technology"; Phone="+81 3 5555 0143"; Enabled=$true; Locked=$false; Groups=@("IT-Admins", "All-Employees") },
        @{ First="Service"; Last="SQLAgent"; SAM="svc-sqlagent"; Parent="OU=Service Accounts,DC=corp,DC=contoso,DC=local"; Title="Service Account"; Dept="Infrastructure"; Phone=""; Enabled=$true; Locked=$false; Groups=@() },
        @{ First="Terminated"; Last="Employee1"; SAM="temp01"; Parent="OU=Disabled Accounts,DC=corp,DC=contoso,DC=local"; Title="Former Contractor"; Dept="Temporary"; Phone=""; Enabled=$false; Locked=$false; Groups=@() }
    )

    foreach ($u in $users) {
        $displayName = "$($u.First) $($u.Last)"
        $mail = "$($u.SAM)@corp.contoso.local"
        $initials = "$($u.First.Substring(0,1))$($u.Last.Substring(0,1))"
        $officeLocation = $(if ($u.Parent -like "*London*") { "London Tower" } elseif ($u.Parent -like "*Tokyo*") { "Tokyo Center" } else { "HQ Redmond" })
        $country = $(if ($u.Parent -like "*London*") { "United Kingdom" } elseif ($u.Parent -like "*Tokyo*") { "Japan" } else { "United States" })
        $cCode = $(if ($u.Parent -like "*London*") { "GB" } elseif ($u.Parent -like "*Tokyo*") { "JP" } else { "US" })
        $countryNum = $(if ($u.Parent -like "*London*") { 826 } elseif ($u.Parent -like "*Tokyo*") { 392 } else { 840 })
        $city = $(if ($u.Parent -like "*London*") { "London" } elseif ($u.Parent -like "*Tokyo*") { "Tokyo" } else { "Redmond" })
        $state = $(if ($u.Parent -like "*London*") { "Greater London" } elseif ($u.Parent -like "*Tokyo*") { "Kanto" } else { "WA" })
        $zip = $(if ($u.Parent -like "*London*") { "EC2A 4NE" } elseif ($u.Parent -like "*Tokyo*") { "100-0001" } else { "98052" })
        $street = $(if ($u.Parent -like "*London*") { "100 Bishopsgate" } elseif ($u.Parent -like "*Tokyo*") { "1-1 Marunouchi" } else { "One Contoso Way" })

        $null = $Script:DemoStore.Objects.Add([PSCustomObject]@{
            ObjectClass          = "user"
            Name                 = $displayName
            displayName          = $displayName
            givenName            = $u.First
            sn                   = $u.Last
            initials             = $initials
            sAMAccountName       = $u.SAM
            sAMAccountType       = 805306368
            userPrincipalName    = "$($u.SAM)@corp.contoso.local"
            mail                 = $mail
            mailNickname         = $u.SAM
            title                = $u.Title
            department           = $u.Dept
            company              = "Contoso Corp"
            office               = $officeLocation
            streetAddress        = $street
            postOfficeBox        = "PO Box 4020"
            l                    = $city
            st                   = $state
            postalCode           = $zip
            co                   = $country
            c                    = $cCode
            countryCode          = $countryNum
            telephoneNumber      = $u.Phone
            homePhone            = "+1 (555) 010-$((Get-Random -Minimum 1000 -Maximum 9999))"
            pager                = ""
            mobile               = "+1 (555) 012-$((Get-Random -Minimum 1000 -Maximum 9999))"
            facsimileTelephoneNumber = "+1 (555) 019-9000"
            ipPhone              = "4$((Get-Random -Minimum 100 -Maximum 999))"
            info                 = "Employee record for $displayName. Department: $($u.Dept)."
            wWWHomePage          = "https://intranet.corp.contoso.local/staff/$($u.SAM)"
            profilePath          = "\\dc01\profiles\$($u.SAM)"
            scriptPath           = "logon.bat"
            homeDirectory        = "\\dc01\home\$($u.SAM)"
            homeDrive            = "H:"
            manager              = $(if ($u.Title -like "*Chief*" -or $u.Title -like "*Director*") { "" } else { "CN=Eleanor Vance,OU=Executive,OU=Corporate,DC=corp,DC=contoso,DC=local" })
            directReports        = $(if ($u.SAM -eq "evance") { @("CN=Marcus Holloway,OU=Executive,OU=Corporate,DC=corp,DC=contoso,DC=local", "CN=Sofia Chen,OU=Executive,OU=Corporate,DC=corp,DC=contoso,DC=local", "CN=Ethan Hunt,OU=Sales & Marketing,OU=Corporate,DC=corp,DC=contoso,DC=local") } else { @() })
            employeeID           = "EMP-$((Get-Random -Minimum 10000 -Maximum 99999))"
            employeeNumber       = "$((Get-Random -Minimum 1000 -Maximum 9999))"
            employeeType         = "Regular Full-Time"
            division             = "Commercial Solutions"
            msTSAllowLogon       = $true
            msTSProfilePath      = "\\dc01\rdsprofiles\$($u.SAM)"
            msTSHomeDirectory    = "\\dc01\rdshome\$($u.SAM)"
            msTSHomeDrive        = "Z:"
            msTSInitialProgram   = ""
            msTSWorkDirectory    = ""
            msTSRemoteControl    = 1
            msNPAllowDialin      = $true
            msNPCallingStationID = ""
            msRADIUSFramedIPAddress = ""
            userCertificate      = @("Cert-ContosoCorp-$($u.SAM)")
            DistinguishedName    = "CN=$displayName,$($u.Parent)"
            ParentDN             = $u.Parent
            Description          = "$($u.Title) - $($u.Dept)"
            Enabled              = $u.Enabled
            LockedOut            = $u.Locked
            PasswordLastSet      = (Get-Date).AddDays(-(Get-Random -Minimum 5 -Maximum 80)).ToString("yyyy-MM-dd HH:mm")
            LastLogonDate        = (Get-Date).AddHours(-(Get-Random -Minimum 1 -Maximum 72)).ToString("yyyy-MM-dd HH:mm")
            lastLogon            = "133748291040000000"
            lastLogonTimestamp   = "133748291040000000"
            badPasswordTime      = "0"
            badPwdCount          = 0
            logonCount           = 42
            userAccountControl   = $(if ($u.Enabled) { 512 } else { 514 })
            PasswordNeverExpires = $false
            MustChangePasswordAtNextLogon = $false
            CannotChangePassword = $false
            AccountExpires       = $null
            adminCount           = $(if ($u.Groups -contains "Domain Admins") { 1 } else { 0 })
            objectCategory       = "CN=Person,CN=Schema,CN=Configuration,DC=corp,DC=contoso,DC=local"
            objectGUID           = [System.Guid]::NewGuid().ToString()
            objectSid            = "S-1-5-21-3829102938-129482910-49201948-$((Get-Random -Minimum 1000 -Maximum 9999))"
            primaryGroupID       = 513
            pwdLastSet           = "133719000000000000"
            uSNCreated           = "$((Get-Random -Minimum 100000 -Maximum 999999))"
            uSNChanged           = "$((Get-Random -Minimum 100000 -Maximum 999999))"
            whenCreated          = (Get-Date).AddDays(-365).ToString("yyyy-MM-dd HH:mm:ss")
            whenChanged          = (Get-Date).AddDays(-2).ToString("yyyy-MM-dd HH:mm:ss")
            MemberOf             = $u.Groups
        })
    }
}

if (-not $Script:IsLiveAD) {
    Initialize-DemoObjects
}

# -----------------------------------------------------------------------------
# Data Access Methods (Abstracted for Live AD & Demo Mode)
# -----------------------------------------------------------------------------
function Get-ADRootInformation {
    if ($Script:IsLiveAD) {
        $adDomain = if ($Domain) { Get-ADDomain -Identity $Domain } else { Get-ADDomain }
        $pdc = if ($Script:ActiveDCName) { $Script:ActiveDCName } else { $adDomain.PDCEmulator }
        $dmode = if ($adDomain.DomainMode) { $adDomain.DomainMode } else { "Windows2016Domain" }
        return [PSCustomObject]@{
            Name              = $adDomain.DNSRoot
            DistinguishedName = $adDomain.DistinguishedName
            PDCEmulator       = $pdc
            DomainMode        = $dmode
            Mode              = "Live Active Directory"
            IsDemo            = $false
        }
    } else {
        $pdc = if ($Script:ActiveDCName) { $Script:ActiveDCName } else { $Script:DemoStore.Domain.PDCEmulator }
        return [PSCustomObject]@{
            Name              = $Script:DemoStore.Domain.Name
            DistinguishedName = $Script:DemoStore.Domain.DistinguishedName
            PDCEmulator       = $pdc
            DomainMode        = $Script:DemoStore.Domain.DomainMode
            Mode              = "Interactive Demo Mode"
            IsDemo            = $true
        }
    }
}

function Set-ADDomainFunctionalLevel {
    param([string]$NewLevel)
    if ($Script:IsLiveAD) {
        Set-ADDomainMode -Identity $Script:RootInfo.DistinguishedName -DomainMode $NewLevel
    } else {
        $Script:DemoStore.Domain.DomainMode = $NewLevel
    }
    $Script:RootInfo = Get-ADRootInformation
}

function Set-ADActiveDomainController {
    param([string]$DCName)
    $Script:ActiveDCName = $DCName
    if (-not $Script:IsLiveAD) {
        $Script:DemoStore.Domain.PDCEmulator = $DCName
    }
    $Script:RootInfo = Get-ADRootInformation
    if ($lblDomainStatus) {
        $modeTag = if ($Script:RootInfo.IsDemo) { "[Demo Mode]" } else { "[Live AD]" }
        $lblDomainStatus.Text = "$modeTag $($Script:RootInfo.Name)`n(DC: $($Script:RootInfo.PDCEmulator))"
    }
    Set-StatusMessage "Switched active Domain Controller to: $DCName"
}

function Invoke-ADDelegateControl {
    param(
        [string]$TargetContainerDN,
        [string[]]$Principals,
        [string[]]$SelectedTasks
    )
    if (-not $Script:IsLiveAD) {
        if (-not $Script:DemoStore.Delegations) {
            $Script:DemoStore.Delegations = [System.Collections.ArrayList]@()
        }
        $null = $Script:DemoStore.Delegations.Add([PSCustomObject]@{
            TargetDN   = $TargetContainerDN
            Principals = $Principals
            Tasks      = $SelectedTasks
            Date       = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        })
    }
    Set-StatusMessage "Delegated control on '$TargetContainerDN' to $($Principals -join ', ') ($($SelectedTasks.Count) tasks)."
}

function Switch-ADTargetDomain {
    param([string]$NewDomainName)
    if ($Script:IsLiveAD) {
        $Script:Domain = $NewDomainName
        $Script:RootInfo = Get-ADRootInformation
    } else {
        $Script:DemoStore.Domain.Name = $NewDomainName.ToUpper()
        $dnParts = $NewDomainName.Split('.') | ForEach-Object { "DC=$_" }
        $Script:DemoStore.Domain.DistinguishedName = $dnParts -join ','
        $Script:RootInfo = Get-ADRootInformation
    }
    if ($lblDomainStatus) {
        $modeTag = if ($Script:RootInfo.IsDemo) { "[Demo Mode]" } else { "[Live AD]" }
        $lblDomainStatus.Text = "$modeTag $($Script:RootInfo.Name)`n(DC: $($Script:RootInfo.PDCEmulator))"
    }
    Populate-DirectoryTree
    Set-StatusMessage "Connected to Domain: $NewDomainName"
}

function Get-ADTreeHierarchy {
    if ($Script:IsLiveAD) {
        $rootInfo = Get-ADRootInformation
        $items = [System.Collections.ArrayList]@()
        # Get OUs
        $ous = Get-ADOrganizationalUnit -Filter * -Properties Name, DistinguishedName
        foreach ($ou in $ous) {
            $parent = ($ou.DistinguishedName -split ',', 2)[1]
            $null = $items.Add([PSCustomObject]@{
                Name              = $ou.Name
                DistinguishedName = $ou.DistinguishedName
                Type              = "ou"
                ParentDN          = $parent
            })
        }
        # Standard default containers
        $defaultContainers = @("Users", "Computers", "Builtin")
        foreach ($c in $defaultContainers) {
            $cdn = "CN=$c,$($rootInfo.DistinguishedName)"
            $null = $items.Add([PSCustomObject]@{
                Name              = $c
                DistinguishedName = $cdn
                Type              = "container"
                ParentDN          = $rootInfo.DistinguishedName
            })
        }
        return $items
    } else {
        return $Script:DemoStore.Containers
    }
}

function Get-ADContainerObjects {
    param([string]$ContainerDN)

    if ($Script:IsLiveAD) {
        $objs = Get-ADObject -Filter * -SearchBase $ContainerDN -SearchScope OneLevel -Properties Name, DisplayName, sAMAccountName, ObjectClass, Description, Enabled, whenChanged, whenCreated, mail, title, department, telephoneNumber
        $results = [System.Collections.ArrayList]@()
        foreach ($o in $objs) {
            $locked = $false
            if ($o.ObjectClass -eq 'user') {
                try {
                    $u = Get-ADUser -Identity $o.DistinguishedName -Properties LockedOut, PasswordLastSet, LastLogonDate, MemberOf
                    $locked = [bool]$u.LockedOut
                } catch {}
            }
            $null = $results.Add([PSCustomObject]@{
                ObjectClass          = $o.ObjectClass
                Name                 = if ($o.DisplayName) { $o.DisplayName } else { $o.Name }
                sAMAccountName       = $o.sAMAccountName
                DistinguishedName    = $o.DistinguishedName
                ParentDN             = $ContainerDN
                Description          = $o.Description
                Enabled              = if ($o.ObjectClass -eq 'user' -or $o.ObjectClass -eq 'computer') { [bool]$o.Enabled } else { $true }
                LockedOut            = $locked
                mail                 = $o.mail
                title                = $o.title
                department           = $o.department
                telephoneNumber      = $o.telephoneNumber
                whenChanged          = if ($o.whenChanged) { $o.whenChanged.ToString("yyyy-MM-dd HH:mm") } else { "" }
                whenCreated          = if ($o.whenCreated) { $o.whenCreated.ToString("yyyy-MM-dd HH:mm") } else { "" }
                MemberOf             = @()
            })
        }
        return $results
    } else {
        return ($Script:DemoStore.Objects | Where-Object { $_.ParentDN -eq $ContainerDN })
    }
}

function Search-ADDirectoryObjects {
    param([string]$Query)

    $q = $Query.Trim().ToLower()
    if ($Script:IsLiveAD) {
        $filter = "Name -like '*$q*' -or sAMAccountName -like '*$q*' -or UserPrincipalName -like '*$q*'"
        return (Get-ADObject -Filter $filter -Properties Name, DisplayName, sAMAccountName, ObjectClass, Description, Enabled, whenChanged)
    } else {
        return ($Script:DemoStore.Objects | Where-Object {
            ($_.Name -and $_.Name.ToLower().Contains($q)) -or
            ($_.sAMAccountName -and $_.sAMAccountName.ToLower().Contains($q)) -or
            ($_.mail -and $_.mail.ToLower().Contains($q)) -or
            ($_.Description -and $_.Description.ToLower().Contains($q)) -or
            ($_.department -and $_.department.ToLower().Contains($q))
        })
    }
}

function Set-ADObjectState {
    param(
        [string]$DistinguishedName,
        [bool]$Enable
    )

    if ($Script:IsLiveAD) {
        if ($Enable) { Enable-ADAccount -Identity $DistinguishedName } else { Disable-ADAccount -Identity $DistinguishedName }
    } else {
        $item = $Script:DemoStore.Objects | Where-Object { $_.DistinguishedName -eq $DistinguishedName }
        if ($item) {
            $item.Enabled = $Enable
            $item.whenChanged = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }
    }
}

function Invoke-ADUnlockAccount {
    param([string]$DistinguishedName)

    if ($Script:IsLiveAD) {
        Unlock-ADAccount -Identity $DistinguishedName
    } else {
        $item = $Script:DemoStore.Objects | Where-Object { $_.DistinguishedName -eq $DistinguishedName }
        if ($item) {
            $item.LockedOut = $false
            $item.whenChanged = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }
    }
}

function Set-ADUserPasswordReset {
    param(
        [string]$DistinguishedName,
        [System.Security.SecureString]$Password,
        [bool]$MustChangeAtNextLogon,
        [bool]$Unlock
    )

    if ($Script:IsLiveAD) {
        Set-ADAccountPassword -Identity $DistinguishedName -NewPassword $Password -Reset
        if ($MustChangeAtNextLogon) {
            Set-ADUser -Identity $DistinguishedName -ChangePasswordAtLogon $true
        }
        if ($Unlock) {
            Unlock-ADAccount -Identity $DistinguishedName
        }
    } else {
        $item = $Script:DemoStore.Objects | Where-Object { $_.DistinguishedName -eq $DistinguishedName }
        if ($item) {
            $item.PasswordLastSet = (Get-Date).ToString("yyyy-MM-dd HH:mm")
            $item.MustChangePasswordAtNextLogon = $MustChangeAtNextLogon
            if ($Unlock) { $item.LockedOut = $false }
            $item.whenChanged = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }
    }
}

function Remove-ADDirectoryObject {
    param([string]$DistinguishedName)

    if ($Script:IsLiveAD) {
        Remove-ADObject -Identity $DistinguishedName -Confirm:$false
    } else {
        $toRemove = $Script:DemoStore.Objects | Where-Object { $_.DistinguishedName -eq $DistinguishedName }
        if ($toRemove) {
            $Script:DemoStore.Objects.Remove($toRemove)
        }
        $ouToRemove = $Script:DemoStore.Containers | Where-Object { $_.DistinguishedName -eq $DistinguishedName }
        if ($ouToRemove) {
            $Script:DemoStore.Containers = @($Script:DemoStore.Containers | Where-Object { $_.DistinguishedName -ne $DistinguishedName })
        }
    }
}

function Move-ADDirectoryObject {
    param(
        [string]$DistinguishedName,
        [string]$TargetContainerDN
    )

    if ($Script:IsLiveAD) {
        Move-ADObject -Identity $DistinguishedName -TargetPath $TargetContainerDN
    } else {
        $item = $Script:DemoStore.Objects | Where-Object { $_.DistinguishedName -eq $DistinguishedName }
        if ($item) {
            $item.ParentDN = $TargetContainerDN
            $leaf = ($DistinguishedName -split ',', 2)[0]
            $item.DistinguishedName = "$leaf,$TargetContainerDN"
            $item.whenChanged = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }
    }
}

# -----------------------------------------------------------------------------
# Main Application UI Construction
# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
# Main Application UI Construction
# -----------------------------------------------------------------------------
$Script:MainForm = New-Object System.Windows.Forms.Form
$Script:MainForm.Text = "ADUCK - Active Directory Users & Computers"
$Script:MainForm.Size = New-Object System.Drawing.Size(1300, 840)
$Script:MainForm.MinimumSize = New-Object System.Drawing.Size(1024, 680)
$Script:MainForm.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$Script:MainForm.BackColor = $Script:Theme.Background
$Script:MainForm.ForeColor = $Script:Theme.TextPrimary
$Script:MainForm.Font = $Script:FontBody
$Script:MainForm.Icon = $Script:DuckIcon

# Apply Windows 10/11 Immersive Dark Title Bar
[ADUCK.NativeMethods]::ApplyDarkTitleBar($Script:MainForm.Handle, ($Script:Theme.Name -eq 'Dark'))

# Header Banner Panel
$pnlHeader = New-Object System.Windows.Forms.Panel
$pnlHeader.Dock = [System.Windows.Forms.DockStyle]::Top
$pnlHeader.Height = 78
$pnlHeader.BackColor = $Script:Theme.HeaderBg
$Script:MainForm.Controls.Add($pnlHeader)

# App Mascot Duck Icon (Header)
$picHeaderDuck = New-Object System.Windows.Forms.PictureBox
$picHeaderDuck.Size = New-Object System.Drawing.Size(42, 42)
$picHeaderDuck.Location = New-Object System.Drawing.Point(18, 18)
$picHeaderDuck.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::CenterImage
$picHeaderDuck.Image = $Script:DuckBitmap
$pnlHeader.Controls.Add($picHeaderDuck)

# App Title & Subtitle
$lblAppTitle = New-Object System.Windows.Forms.Label
$lblAppTitle.Text = "ADUCK"
$lblAppTitle.Font = $Script:FontLargeTitle
$lblAppTitle.ForeColor = $Script:Theme.TextPrimary
$lblAppTitle.Location = New-Object System.Drawing.Point(68, 15)
$lblAppTitle.AutoSize = $true
$pnlHeader.Controls.Add($lblAppTitle)

$rootInfo = Get-ADRootInformation
$Script:RootInfo = $rootInfo
$lblAppSubtitle = New-Object System.Windows.Forms.Label
$lblAppSubtitle.Text = "Active Directory Users & Computers - Enterprise Console"
$lblAppSubtitle.UseMnemonic = $false
$lblAppSubtitle.Font = $Script:FontSmall
$lblAppSubtitle.ForeColor = $Script:Theme.TextSecondary
$lblAppSubtitle.Location = New-Object System.Drawing.Point(70, 44)
$lblAppSubtitle.AutoSize = $true
$pnlHeader.Controls.Add($lblAppSubtitle)

# Domain Connection Badge Chip (Sized and positioned to prevent any title or action bar overlap)
$pnlDomainBadge = New-Object System.Windows.Forms.Panel
$pnlDomainBadge.Location = New-Object System.Drawing.Point(375, 16)
$pnlDomainBadge.Size = New-Object System.Drawing.Size(245, 46)
$pnlDomainBadge.BackColor = if ($rootInfo.IsDemo) { $Script:Theme.WarningBg } else { $Script:Theme.SuccessBg }
$pnlDomainBadge.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$pnlHeader.Controls.Add($pnlDomainBadge)

$lblDomainStatus = New-Object System.Windows.Forms.Label
$modeTag = if ($rootInfo.IsDemo) { "[Demo Mode]" } else { "[Live AD]" }
$lblDomainStatus.Text = "$modeTag $($rootInfo.Name)`n(DC: $($rootInfo.PDCEmulator))"
$lblDomainStatus.ForeColor = if ($rootInfo.IsDemo) { $Script:Theme.Warning } else { $Script:Theme.Success }
$lblDomainStatus.Font = $Script:FontSmallBold
$lblDomainStatus.Dock = [System.Windows.Forms.DockStyle]::Fill
$lblDomainStatus.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$pnlDomainBadge.Controls.Add($lblDomainStatus)

$pnlHeader.Add_Resize({
    if ($pnlHeader.Width -ge 1180) {
        $pnlDomainBadge.Location = New-Object System.Drawing.Point(375, 16)
        $pnlDomainBadge.Visible = $true
    } elseif ($pnlHeader.Width -ge 960) {
        $badgeX = [Math]::Max(365, $pnlHeader.Width - 575 - $pnlDomainBadge.Width)
        $pnlDomainBadge.Location = New-Object System.Drawing.Point($badgeX, 16)
        $pnlDomainBadge.Visible = $true
    } else {
        $pnlDomainBadge.Visible = $false
    }
})

# Header Right Controls (Quick Action Bar & Search)
$pnlHeaderRight = New-Object System.Windows.Forms.Panel
$pnlHeaderRight.Dock = [System.Windows.Forms.DockStyle]::Right
$pnlHeaderRight.Width = 560
$pnlHeaderRight.BackColor = [System.Drawing.Color]::Transparent
$pnlHeader.Controls.Add($pnlHeaderRight)

# Search Box
$txtSearch = New-Object System.Windows.Forms.TextBox
$txtSearch.Location = New-Object System.Drawing.Point(12, 24)
$txtSearch.Size = New-Object System.Drawing.Size(220, 28)
$txtSearch.BackColor = $Script:Theme.InputBg
$txtSearch.ForeColor = $Script:Theme.TextSecondary
$txtSearch.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$txtSearch.Font = $Script:FontBody
$txtSearch.Text = "Search directory (Name, SAM, Dept)..."
$pnlHeaderRight.Controls.Add($txtSearch)

# Handle Search placeholder text
$txtSearch.Add_GotFocus({
    if ($txtSearch.Text -eq "Search directory (Name, SAM, Dept)...") {
        $txtSearch.Text = ""
        $txtSearch.ForeColor = $Script:Theme.TextPrimary
    }
})
$txtSearch.Add_LostFocus({
    if ([string]::IsNullOrWhiteSpace($txtSearch.Text)) {
        $txtSearch.Text = "Search directory (Name, SAM, Dept)..."
        $txtSearch.ForeColor = $Script:Theme.TextSecondary
    }
})

# Search Action Button (Clean text, perfectly aligned with input)
$btnSearch = New-Object ADUCK.DarkButton
$btnSearch.Text = "Search"
$btnSearch.Location = New-Object System.Drawing.Point(238, 23)
$btnSearch.Size = New-Object System.Drawing.Size(68, 30)
$btnSearch.Font = $Script:FontSmallBold
$btnSearch.SetPalette(
    $Script:Theme.BtnBg,
    $Script:Theme.TextPrimary,
    $Script:Theme.BtnBorder,
    $Script:Theme.BtnHoverBg,
    $Script:Theme.TextPrimary,
    $Script:Theme.BtnHoverBorder,
    $Script:Theme.BtnDisabledBg,
    $Script:Theme.BtnDisabledFg,
    $Script:Theme.BtnDisabledBorder
)
$pnlHeaderRight.Controls.Add($btnSearch)

# Quick New Object Button Dropdown
$btnNewQuick = New-Object ADUCK.DarkButton
$btnNewQuick.Text = "+ New Object v"
$btnNewQuick.Location = New-Object System.Drawing.Point(312, 23)
$btnNewQuick.Size = New-Object System.Drawing.Size(115, 30)
$btnNewQuick.Font = $Script:FontSmallBold
$btnNewQuick.SetPalette(
    $Script:Theme.AccentDark,
    [System.Drawing.Color]::White,
    $Script:Theme.Accent,
    $Script:Theme.AccentHover,
    [System.Drawing.Color]::White,
    $Script:Theme.Accent,
    $Script:Theme.BtnDisabledBg,
    $Script:Theme.BtnDisabledFg,
    $Script:Theme.BtnDisabledBorder
)
$pnlHeaderRight.Controls.Add($btnNewQuick)

# Refresh Button
$btnRefreshAll = New-Object ADUCK.DarkButton
$btnRefreshAll.Text = "Refresh"
$btnRefreshAll.Location = New-Object System.Drawing.Point(433, 23)
$btnRefreshAll.Size = New-Object System.Drawing.Size(62, 30)
$btnRefreshAll.Font = $Script:FontSmallBold
$btnRefreshAll.SetPalette(
    $Script:Theme.BtnBg,
    $Script:Theme.TextPrimary,
    $Script:Theme.BtnBorder,
    $Script:Theme.BtnHoverBg,
    $Script:Theme.TextPrimary,
    $Script:Theme.BtnHoverBorder,
    $Script:Theme.BtnDisabledBg,
    $Script:Theme.BtnDisabledFg,
    $Script:Theme.BtnDisabledBorder
)
$pnlHeaderRight.Controls.Add($btnRefreshAll)

# Theme Toggle Button (Dark / Light)
$btnThemeToggle = New-Object ADUCK.DarkButton
$btnThemeToggle.Text = "Theme"
$btnThemeToggle.Location = New-Object System.Drawing.Point(501, 23)
$btnThemeToggle.Size = New-Object System.Drawing.Size(52, 30)
$btnThemeToggle.Font = $Script:FontSmallBold
$btnThemeToggle.SetPalette(
    $Script:Theme.BtnBg,
    $Script:Theme.TextPrimary,
    $Script:Theme.BtnBorder,
    $Script:Theme.BtnHoverBg,
    $Script:Theme.TextPrimary,
    $Script:Theme.BtnHoverBorder,
    $Script:Theme.BtnDisabledBg,
    $Script:Theme.BtnDisabledFg,
    $Script:Theme.BtnDisabledBorder
)
$pnlHeaderRight.Controls.Add($btnThemeToggle)

# Status Bar (Docked Bottom)
$statusStrip = New-Object System.Windows.Forms.StatusStrip
$statusStrip.Renderer = $Script:ToolStripRenderer
$statusStrip.BackColor = $Script:Theme.HeaderBg
$statusStrip.ForeColor = $Script:Theme.TextSecondary
$Script:MainForm.Controls.Add($statusStrip)

$lblStatusMessage = New-Object System.Windows.Forms.ToolStripStatusLabel
$lblStatusMessage.Text = "Ready."
$lblStatusMessage.Spring = $true
$lblStatusMessage.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
[void]$statusStrip.Items.Add($lblStatusMessage)

$lblStatusDomain = New-Object System.Windows.Forms.ToolStripStatusLabel
$lblStatusDomain.Text = "Domain: $($rootInfo.Name)"
$lblStatusDomain.BorderSides = [System.Windows.Forms.ToolStripStatusLabelBorderSides]::Left
[void]$statusStrip.Items.Add($lblStatusDomain)

$lblStatusUser = New-Object System.Windows.Forms.ToolStripStatusLabel
$lblStatusUser.Text = "Admin: $env:USERDOMAIN\$env:USERNAME"
$lblStatusUser.BorderSides = [System.Windows.Forms.ToolStripStatusLabelBorderSides]::Left
[void]$statusStrip.Items.Add($lblStatusUser)

$lblStatusCount = New-Object System.Windows.Forms.ToolStripStatusLabel
$lblStatusCount.Text = "0 items"
$lblStatusCount.BorderSides = [System.Windows.Forms.ToolStripStatusLabelBorderSides]::Left
[void]$statusStrip.Items.Add($lblStatusCount)

# Main Body SplitContainer (Left: Directory Tree, Right: Object Views & Inspector)
$splitMain = New-Object System.Windows.Forms.SplitContainer
$splitMain.Dock = [System.Windows.Forms.DockStyle]::Fill
$splitMain.FixedPanel = [System.Windows.Forms.FixedPanel]::Panel1
$splitMain.SplitterDistance = 280
$splitMain.SplitterWidth = 6
$splitMain.BackColor = $Script:Theme.Border
$Script:MainForm.Controls.Add($splitMain)
$pnlHeader.SendToBack()
$statusStrip.SendToBack()

# -----------------------------------------------------------------------------
# Left Navigation Pane (Directory TreeView)
# -----------------------------------------------------------------------------
$pnlTreeContainer = New-Object System.Windows.Forms.Panel
$pnlTreeContainer.Dock = [System.Windows.Forms.DockStyle]::Fill
$pnlTreeContainer.BackColor = $Script:Theme.Surface
$splitMain.Panel1.Controls.Add($pnlTreeContainer)

$pnlTreeHeader = New-Object System.Windows.Forms.Panel
$pnlTreeHeader.Dock = [System.Windows.Forms.DockStyle]::Top
$pnlTreeHeader.Height = 36
$pnlTreeHeader.BackColor = $Script:Theme.SurfaceAlt
$pnlTreeContainer.Controls.Add($pnlTreeHeader)

$lblTreeTitle = New-Object System.Windows.Forms.Label
$lblTreeTitle.Text = "DIRECTORY TREE"
$lblTreeTitle.Font = $Script:FontSmallBold
$lblTreeTitle.ForeColor = $Script:Theme.TextSecondary
$lblTreeTitle.Location = New-Object System.Drawing.Point(12, 10)
$lblTreeTitle.AutoSize = $true
$pnlTreeHeader.Controls.Add($lblTreeTitle)

$treeView = New-Object System.Windows.Forms.TreeView
$treeView.Dock = [System.Windows.Forms.DockStyle]::Fill
$treeView.BackColor = $Script:Theme.Surface
$treeView.ForeColor = $Script:Theme.TextPrimary
$treeView.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$treeView.Font = $Script:FontBody
$treeView.ImageList = $Script:ImageList
$treeView.FullRowSelect = $true
$treeView.ShowLines = $true
$treeView.LineColor = $Script:Theme.Border
$pnlTreeContainer.Controls.Add($treeView)

# Ensure header docks above TreeView without obscuring top nodes
$pnlTreeHeader.SendToBack()

# -----------------------------------------------------------------------------
# Right Pane: Top Path/Breadcrumb + Filter Chips + ListView + Inspector Drawer
# -----------------------------------------------------------------------------
$pnlRightContainer = New-Object System.Windows.Forms.Panel
$pnlRightContainer.Dock = [System.Windows.Forms.DockStyle]::Fill
$pnlRightContainer.BackColor = $Script:Theme.Background
$splitMain.Panel2.Controls.Add($pnlRightContainer)

# Breadcrumb & Filter Bar
$pnlRightTop = New-Object System.Windows.Forms.Panel
$pnlRightTop.Dock = [System.Windows.Forms.DockStyle]::Top
$pnlRightTop.Height = 52
$pnlRightTop.BackColor = $Script:Theme.SurfaceAlt
$pnlRightContainer.Controls.Add($pnlRightTop)

# Filter Pills Panel (Right aligned inside Top Bar)
$pnlFilters = New-Object System.Windows.Forms.FlowLayoutPanel
$pnlFilters.Dock = [System.Windows.Forms.DockStyle]::Right
$pnlFilters.Width = 410
$pnlFilters.FlowDirection = [System.Windows.Forms.FlowDirection]::RightToLeft
$pnlFilters.Padding = New-Object System.Windows.Forms.Padding(0, 10, 14, 0)
$pnlFilters.BackColor = [System.Drawing.Color]::Transparent
$pnlRightTop.Controls.Add($pnlFilters)

$lblBreadcrumb = New-Object System.Windows.Forms.Label
$lblBreadcrumb.Text = "Container: $($rootInfo.Name)"
$lblBreadcrumb.Font = $Script:FontBodyBold
$lblBreadcrumb.ForeColor = $Script:Theme.TextPrimary
$lblBreadcrumb.Location = New-Object System.Drawing.Point(14, 16)
$lblBreadcrumb.Size = New-Object System.Drawing.Size(460, 24)
$lblBreadcrumb.AutoEllipsis = $true
$lblBreadcrumb.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$pnlRightTop.Controls.Add($lblBreadcrumb)

$pnlRightTop.Add_Resize({
    $lblBreadcrumb.Width = [Math]::Max(120, $pnlRightTop.Width - $pnlFilters.Width - 25)
})

$Script:CurrentTypeFilter = 'All'

function New-FilterButton {
    param([string]$Text, [string]$FilterKey, [bool]$IsDefault = $false)

    $btnFilter = New-Object ADUCK.DarkButton
    $btnFilter.Text = $Text
    $btnFilter.Size = New-Object System.Drawing.Size(90, 30)
    $btnFilter.Font = $Script:FontSmallBold
    $btnFilter.Tag = $FilterKey

    if ($IsDefault) {
        $btnFilter.SetPalette(
            $Script:Theme.AccentDark,
            [System.Drawing.Color]::White,
            $Script:Theme.Accent,
            $Script:Theme.AccentHover,
            [System.Drawing.Color]::White,
            $Script:Theme.Accent,
            $Script:Theme.BtnDisabledBg,
            $Script:Theme.BtnDisabledFg,
            $Script:Theme.BtnDisabledBorder
        )
    } else {
        $btnFilter.SetPalette(
            $Script:Theme.BtnBg,
            $Script:Theme.TextSecondary,
            $Script:Theme.BtnBorder,
            $Script:Theme.BtnHoverBg,
            $Script:Theme.TextPrimary,
            $Script:Theme.BtnHoverBorder,
            $Script:Theme.BtnDisabledBg,
            $Script:Theme.BtnDisabledFg,
            $Script:Theme.BtnDisabledBorder
        )
    }

    $btnFilter.Add_Click({
        param($sender, $e)
        $Script:CurrentTypeFilter = $sender.Tag
        foreach ($c in $pnlFilters.Controls) {
            if ($c -is [ADUCK.DarkButton]) {
                if ($c.Tag -eq $Script:CurrentTypeFilter) {
                    $c.SetPalette(
                        $Script:Theme.AccentDark,
                        [System.Drawing.Color]::White,
                        $Script:Theme.Accent,
                        $Script:Theme.AccentHover,
                        [System.Drawing.Color]::White,
                        $Script:Theme.Accent,
                        $Script:Theme.BtnDisabledBg,
                        $Script:Theme.BtnDisabledFg,
                        $Script:Theme.BtnDisabledBorder
                    )
                } else {
                    $c.SetPalette(
                        $Script:Theme.BtnBg,
                        $Script:Theme.TextSecondary,
                        $Script:Theme.BtnBorder,
                        $Script:Theme.BtnHoverBg,
                        $Script:Theme.TextPrimary,
                        $Script:Theme.BtnHoverBorder,
                        $Script:Theme.BtnDisabledBg,
                        $Script:Theme.BtnDisabledFg,
                        $Script:Theme.BtnDisabledBorder
                    )
                }
            } else {
                if ($c.Tag -eq $Script:CurrentTypeFilter) {
                    $c.BackColor = $Script:Theme.AccentDark
                    $c.ForeColor = [System.Drawing.Color]::White
                    $c.FlatAppearance.BorderColor = $Script:Theme.Accent
                    $c.FlatAppearance.MouseOverBackColor = $Script:Theme.AccentHover
                } else {
                    $c.BackColor = $Script:Theme.Surface
                    $c.ForeColor = $Script:Theme.TextSecondary
                    $c.FlatAppearance.BorderColor = $Script:Theme.Border
                    $c.FlatAppearance.MouseOverBackColor = $Script:Theme.SurfaceAlt
                }
            }
        }
        Apply-ObjectFilter
    })
    return $btnFilter
}

$btnFComputers = New-FilterButton -Text "Computers" -FilterKey "computer"
$btnFGroups    = New-FilterButton -Text "Groups" -FilterKey "group"
$btnFUsers     = New-FilterButton -Text "Users" -FilterKey "user"
$btnFAll       = New-FilterButton -Text "All Items" -FilterKey "All" -IsDefault $true

$pnlFilters.Controls.Add($btnFComputers)
$pnlFilters.Controls.Add($btnFGroups)
$pnlFilters.Controls.Add($btnFUsers)
$pnlFilters.Controls.Add($btnFAll)

# SplitContainer for ListView (top) and Inspector Drawer (bottom)
$splitRight = New-Object System.Windows.Forms.SplitContainer
$splitRight.Dock = [System.Windows.Forms.DockStyle]::Fill
$splitRight.Orientation = [System.Windows.Forms.Orientation]::Horizontal
$splitRight.FixedPanel = [System.Windows.Forms.FixedPanel]::Panel2
$splitRight.SplitterDistance = 540
$splitRight.SplitterWidth = 6
$splitRight.BackColor = $Script:Theme.Border
$pnlRightContainer.Controls.Add($splitRight)

# Ensure Top Bar docks above SplitContainer without obscuring ListView column headers
$pnlRightTop.SendToBack()

# -----------------------------------------------------------------------------
# Object ListView
# -----------------------------------------------------------------------------
$listView = New-Object System.Windows.Forms.ListView
$listView.Dock = [System.Windows.Forms.DockStyle]::Fill
$listView.View = [System.Windows.Forms.View]::Details
$listView.FullRowSelect = $true
$listView.GridLines = $false
$listView.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$listView.BackColor = $Script:Theme.Surface
$listView.ForeColor = $Script:Theme.TextPrimary
$listView.Font = $Script:FontBody
$listView.SmallImageList = $Script:ImageList
$listView.MultiSelect = $false
$listView.HideSelection = $false
$splitRight.Panel1.Controls.Add($listView)

# Column Sorter
$Script:ColumnSorter = New-Object ADUCK.ListViewColumnSorter
$listView.ListViewItemSorter = $Script:ColumnSorter

# Columns
$colName = $listView.Columns.Add("Name", 220)
$colType = $listView.Columns.Add("Type", 100)
$colSam  = $listView.Columns.Add("Logon Name (sAMAccountName)", 180)
$colStat = $listView.Columns.Add("Status", 100)
$colDesc = $listView.Columns.Add("Description", 260)
$colDept = $listView.Columns.Add("Department", 140)
$colMod  = $listView.Columns.Add("Modified", 140)

# Column Header Click Sorting
$listView.Add_ColumnClick({
    param($sender, $e)
    if ($e.Column -eq $Script:ColumnSorter.ColumnIndex) {
        if ($Script:ColumnSorter.Order -eq [System.Windows.Forms.SortOrder]::Ascending) {
            $Script:ColumnSorter.Order = [System.Windows.Forms.SortOrder]::Descending
        } else {
            $Script:ColumnSorter.Order = [System.Windows.Forms.SortOrder]::Ascending
        }
    } else {
        $Script:ColumnSorter.ColumnIndex = $e.Column
        $Script:ColumnSorter.Order = [System.Windows.Forms.SortOrder]::Ascending
    }
    $listView.Sort()
})

# -----------------------------------------------------------------------------
# Bottom Inspector Drawer (Quick Object Details & Quick Actions)
# -----------------------------------------------------------------------------
$pnlInspector = New-Object System.Windows.Forms.Panel
$pnlInspector.Dock = [System.Windows.Forms.DockStyle]::Fill
$pnlInspector.BackColor = $Script:Theme.SurfaceAlt
$pnlInspector.Padding = New-Object System.Windows.Forms.Padding(16, 12, 16, 12)
$splitRight.Panel2.Controls.Add($pnlInspector)

# Inspector Header / Avatar Box
$picInspectorAvatar = New-Object System.Windows.Forms.PictureBox
$picInspectorAvatar.Size = New-Object System.Drawing.Size(56, 56)
$picInspectorAvatar.Location = New-Object System.Drawing.Point(16, 16)
$picInspectorAvatar.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::CenterImage
$picInspectorAvatar.BackColor = $Script:Theme.ChipBg
$pnlInspector.Controls.Add($picInspectorAvatar)

# Identity Details
$lblInspName = New-Object System.Windows.Forms.Label
$lblInspName.Text = "Select an object to inspect details"
$lblInspName.Font = $Script:FontTitle
$lblInspName.ForeColor = $Script:Theme.TextPrimary
$lblInspName.Location = New-Object System.Drawing.Point(86, 16)
$lblInspName.AutoSize = $true
$pnlInspector.Controls.Add($lblInspName)

$lblInspSub = New-Object System.Windows.Forms.Label
$lblInspSub.Text = "No object selected."
$lblInspSub.Font = $Script:FontSmall
$lblInspSub.ForeColor = $Script:Theme.TextSecondary
$lblInspSub.Location = New-Object System.Drawing.Point(88, 42)
$lblInspSub.AutoSize = $true
$pnlInspector.Controls.Add($lblInspSub)

# Detail Badges & Attribute Chips
$lblInspAttr1 = New-Object System.Windows.Forms.Label
$lblInspAttr1.Font = $Script:FontSmall
$lblInspAttr1.ForeColor = $Script:Theme.TextPrimary
$lblInspAttr1.Location = New-Object System.Drawing.Point(88, 68)
$lblInspAttr1.Size = New-Object System.Drawing.Size(245, 22)
$lblInspAttr1.AutoEllipsis = $true
$pnlInspector.Controls.Add($lblInspAttr1)

$lblInspAttr2 = New-Object System.Windows.Forms.Label
$lblInspAttr2.Font = $Script:FontSmall
$lblInspAttr2.ForeColor = $Script:Theme.TextPrimary
$lblInspAttr2.Location = New-Object System.Drawing.Point(88, 92)
$lblInspAttr2.Size = New-Object System.Drawing.Size(245, 22)
$lblInspAttr2.AutoEllipsis = $true
$pnlInspector.Controls.Add($lblInspAttr2)

$lblInspAttr3 = New-Object System.Windows.Forms.Label
$lblInspAttr3.Font = $Script:FontSmall
$lblInspAttr3.ForeColor = $Script:Theme.TextPrimary
$lblInspAttr3.Location = New-Object System.Drawing.Point(345, 68)
$lblInspAttr3.Size = New-Object System.Drawing.Size(265, 22)
$lblInspAttr3.AutoEllipsis = $true
$pnlInspector.Controls.Add($lblInspAttr3)

$lblInspAttr4 = New-Object System.Windows.Forms.Label
$lblInspAttr4.Font = $Script:FontSmall
$lblInspAttr4.ForeColor = $Script:Theme.TextPrimary
$lblInspAttr4.Location = New-Object System.Drawing.Point(345, 92)
$lblInspAttr4.Size = New-Object System.Drawing.Size(265, 22)
$lblInspAttr4.AutoEllipsis = $true
$pnlInspector.Controls.Add($lblInspAttr4)

# Inspector Action Buttons Panel (Right side of Inspector)
$pnlInspActions = New-Object System.Windows.Forms.FlowLayoutPanel
$pnlInspActions.Dock = [System.Windows.Forms.DockStyle]::Right
$pnlInspActions.Width = 290
$pnlInspActions.Padding = New-Object System.Windows.Forms.Padding(0, 4, 12, 0)
$pnlInspActions.FlowDirection = [System.Windows.Forms.FlowDirection]::RightToLeft
$pnlInspActions.BackColor = [System.Drawing.Color]::Transparent
$pnlInspector.Controls.Add($pnlInspActions)

function New-ActionButton {
    param([string]$Text, [string]$Tag, [int]$Width = 88, [System.Drawing.Color]$HoverColor = [System.Drawing.Color]::Empty)

    $actionBtn = New-Object ADUCK.DarkButton
    $actionBtn.Text = $Text
    $actionBtn.Tag = $Tag
    $actionBtn.Size = New-Object System.Drawing.Size($Width, 32)
    $actionBtn.Font = $Script:FontSmallBold
    $actionBtn.Margin = New-Object System.Windows.Forms.Padding(3)

    $hBg = if ($HoverColor -and $HoverColor -ne [System.Drawing.Color]::Empty) { $HoverColor } else { $Script:Theme.BtnHoverBg }
    $hBorder = if ($HoverColor -eq $Script:Theme.WarningBg) { $Script:Theme.Warning } elseif ($HoverColor -and $HoverColor -ne [System.Drawing.Color]::Empty) { $Script:Theme.Accent } else { $Script:Theme.BtnHoverBorder }

    $actionBtn.SetPalette(
        $Script:Theme.BtnBg,
        $Script:Theme.TextPrimary,
        $Script:Theme.BtnBorder,
        $hBg,
        $Script:Theme.TextPrimary,
        $hBorder,
        $Script:Theme.BtnDisabledBg,
        $Script:Theme.BtnDisabledFg,
        $Script:Theme.BtnDisabledBorder
    )
    return $actionBtn
}

$btnInspProps  = New-ActionButton -Text "Properties" -Tag "props" -Width 92
$btnInspMove   = New-ActionButton -Text "Move..." -Tag "move" -Width 82
$btnInspUnlock = New-ActionButton -Text "Unlock" -Tag "unlock" -Width 80 -HoverColor $Script:Theme.WarningBg
$btnInspToggle = New-ActionButton -Text "Disable" -Tag "toggle" -Width 80
$btnInspPass   = New-ActionButton -Text "Reset Pass" -Tag "pass" -Width 92 -HoverColor $Script:Theme.AccentDark

$pnlInspActions.Controls.Add($btnInspProps)
$pnlInspActions.Controls.Add($btnInspMove)
$pnlInspActions.Controls.Add($btnInspUnlock)
$pnlInspActions.Controls.Add($btnInspToggle)
$pnlInspActions.Controls.Add($btnInspPass)

# -----------------------------------------------------------------------------
# Context Menus (Dark-Themed)
# -----------------------------------------------------------------------------
# TreeView Context Menu (Specialized for Domain Root, OUs, and Containers)
$treeContextMenu = New-Object System.Windows.Forms.ContextMenuStrip
$treeContextMenu.Renderer = $Script:ToolStripRenderer
$treeContextMenu.BackColor = $Script:Theme.Surface
$treeContextMenu.ForeColor = $Script:Theme.TextPrimary
$treeContextMenu.Font = $Script:FontBody

# Domain Root and Container specific administrative actions
$mnuTreeDelegate  = $treeContextMenu.Items.Add("Delegate Control...")
$mnuTreeChangeDom = $treeContextMenu.Items.Add("Change Domain...")
$mnuTreeChangeDC  = $treeContextMenu.Items.Add("Change Domain Controller...")
$mnuTreeRaiseDFL  = $treeContextMenu.Items.Add("Raise domain functional level...")
$mnuTreeSepDomain = $treeContextMenu.Items.Add("-")

$mnuTreeNewUser  = $treeContextMenu.Items.Add("New User...")
$mnuTreeNewGroup = $treeContextMenu.Items.Add("New Group...")
$mnuTreeNewComp  = $treeContextMenu.Items.Add("New Computer...")
$mnuTreeNewOU    = $treeContextMenu.Items.Add("New Organizational Unit...")
$treeContextMenu.Items.Add("-") | Out-Null
$mnuTreeRefresh  = $treeContextMenu.Items.Add("Refresh Container")
$mnuTreeCopyDN   = $treeContextMenu.Items.Add("Copy Distinguished Name")

# ListView Item Context Menu
$itemContextMenu = New-Object System.Windows.Forms.ContextMenuStrip
$itemContextMenu.Renderer = $Script:ToolStripRenderer
$itemContextMenu.BackColor = $Script:Theme.Surface
$itemContextMenu.ForeColor = $Script:Theme.TextPrimary
$itemContextMenu.Font = $Script:FontBody

$mnuItemPass   = $itemContextMenu.Items.Add("Reset Password...")
$mnuItemToggle = $itemContextMenu.Items.Add("Disable Account")
$mnuItemUnlock = $itemContextMenu.Items.Add("Unlock Account")
$itemContextMenu.Items.Add("-") | Out-Null
$mnuItemAddGrp = $itemContextMenu.Items.Add("Add to Group...")
$mnuItemMove   = $itemContextMenu.Items.Add("Move Object...")
$mnuItemDel    = $itemContextMenu.Items.Add("Delete Object")
$itemContextMenu.Items.Add("-") | Out-Null
$mnuItemCopyDN = $itemContextMenu.Items.Add("Copy Distinguished Name")
$mnuItemProps  = $itemContextMenu.Items.Add("Properties")

$listView.ContextMenuStrip = $itemContextMenu
$treeView.ContextMenuStrip = $treeContextMenu

# "New Quick" Button Dropdown Menu
$newQuickMenu = New-Object System.Windows.Forms.ContextMenuStrip
$newQuickMenu.Renderer = $Script:ToolStripRenderer
$newQuickMenu.BackColor = $Script:Theme.Surface
$newQuickMenu.ForeColor = $Script:Theme.TextPrimary
$newQuickMenu.Font = $Script:FontBody

$mnuQNewUser = $newQuickMenu.Items.Add("New User")
$mnuQNewGrp  = $newQuickMenu.Items.Add("New Group")
$mnuQNewComp = $newQuickMenu.Items.Add("New Computer")
$mnuQNewOU   = $newQuickMenu.Items.Add("New Organizational Unit")

$btnNewQuick.Add_Click({
    $newQuickMenu.Show($btnNewQuick, 0, $btnNewQuick.Height)
})

# -----------------------------------------------------------------------------
# Dialogs: New User, New Group, New Computer, New OU, Reset Pass, Properties, Move
# -----------------------------------------------------------------------------

# Helper for Modal Dialog Template
function New-ModernDialog {
    param([string]$Title, [int]$Width = 520, [int]$Height = 480)

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = $Title
    $dlg.Size = New-Object System.Drawing.Size($Width, $Height)
    $dlg.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.BackColor = $Script:Theme.Surface
    $dlg.ForeColor = $Script:Theme.TextPrimary
    $dlg.Font = $Script:FontBody
    if ($Script:DuckIcon) { $dlg.Icon = $Script:DuckIcon }

    [ADUCK.NativeMethods]::ApplyDarkTitleBar($dlg.Handle, ($Script:Theme.Name -eq 'Dark'))
    return $dlg
}

# Dialog: New User
function Show-NewUserDialog {
    param([string]$TargetContainerDN)

    $dlg = New-ModernDialog -Title "Create New Active Directory User" -Width 540 -Height 580

    $lblHdr = New-Object System.Windows.Forms.Label
    $lblHdr.Text = "New User Details"
    $lblHdr.Font = $Script:FontTitle
    $lblHdr.Location = New-Object System.Drawing.Point(24, 20)
    $lblHdr.AutoSize = $true
    $dlg.Controls.Add($lblHdr)

    # First Name
    $lblFirst = New-Object System.Windows.Forms.Label
    $lblFirst.Text = "First name:"
    $lblFirst.Location = New-Object System.Drawing.Point(24, 60)
    $lblFirst.AutoSize = $true
    $dlg.Controls.Add($lblFirst)

    $txtFirst = New-Object System.Windows.Forms.TextBox
    $txtFirst.Location = New-Object System.Drawing.Point(24, 82)
    $txtFirst.Size = New-Object System.Drawing.Size(230, 26)
    $txtFirst.BackColor = $Script:Theme.InputBg
    $txtFirst.ForeColor = $Script:Theme.TextPrimary
    $txtFirst.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $dlg.Controls.Add($txtFirst)

    # Last Name
    $lblLast = New-Object System.Windows.Forms.Label
    $lblLast.Text = "Last name:"
    $lblLast.Location = New-Object System.Drawing.Point(270, 60)
    $lblLast.AutoSize = $true
    $dlg.Controls.Add($lblLast)

    $txtLast = New-Object System.Windows.Forms.TextBox
    $txtLast.Location = New-Object System.Drawing.Point(270, 82)
    $txtLast.Size = New-Object System.Drawing.Size(230, 26)
    $txtLast.BackColor = $Script:Theme.InputBg
    $txtLast.ForeColor = $Script:Theme.TextPrimary
    $txtLast.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $dlg.Controls.Add($txtLast)

    # Full / Display Name
    $lblDisplay = New-Object System.Windows.Forms.Label
    $lblDisplay.Text = "Full display name:"
    $lblDisplay.Location = New-Object System.Drawing.Point(24, 120)
    $lblDisplay.AutoSize = $true
    $dlg.Controls.Add($lblDisplay)

    $txtDisplay = New-Object System.Windows.Forms.TextBox
    $txtDisplay.Location = New-Object System.Drawing.Point(24, 142)
    $txtDisplay.Size = New-Object System.Drawing.Size(476, 26)
    $txtDisplay.BackColor = $Script:Theme.InputBg
    $txtDisplay.ForeColor = $Script:Theme.TextPrimary
    $txtDisplay.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $dlg.Controls.Add($txtDisplay)

    # Auto-generate display name and SAM as user types
    $autoUpdate = {
        $first = $txtFirst.Text.Trim()
        $last = $txtLast.Text.Trim()
        if ($first -or $last) {
            $txtDisplay.Text = "$first $last".Trim()
            $sam = ""
            if ($first -and $last) { $sam = "$($first.Substring(0,1))$last".ToLower() }
            elseif ($first) { $sam = $first.ToLower() }
            elseif ($last) { $sam = $last.ToLower() }
            $txtSam.Text = $sam
        }
    }
    $txtFirst.Add_TextChanged($autoUpdate)
    $txtLast.Add_TextChanged($autoUpdate)

    # User Logon Name (sAMAccountName)
    $lblSam = New-Object System.Windows.Forms.Label
    $lblSam.Text = "User logon name (sAMAccountName):"
    $lblSam.Location = New-Object System.Drawing.Point(24, 180)
    $lblSam.AutoSize = $true
    $dlg.Controls.Add($lblSam)

    $txtSam = New-Object System.Windows.Forms.TextBox
    $txtSam.Location = New-Object System.Drawing.Point(24, 202)
    $txtSam.Size = New-Object System.Drawing.Size(476, 26)
    $txtSam.BackColor = $Script:Theme.InputBg
    $txtSam.ForeColor = $Script:Theme.TextPrimary
    $txtSam.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $dlg.Controls.Add($txtSam)

    # Password
    $lblPass = New-Object System.Windows.Forms.Label
    $lblPass.Text = "Password:"
    $lblPass.Location = New-Object System.Drawing.Point(24, 240)
    $lblPass.AutoSize = $true
    $dlg.Controls.Add($lblPass)

    $txtPass = New-Object System.Windows.Forms.TextBox
    $txtPass.Location = New-Object System.Drawing.Point(24, 262)
    $txtPass.Size = New-Object System.Drawing.Size(476, 26)
    $txtPass.PasswordChar = [char]0x25CF
    $txtPass.BackColor = $Script:Theme.InputBg
    $txtPass.ForeColor = $Script:Theme.TextPrimary
    $txtPass.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $dlg.Controls.Add($txtPass)

    # Confirm Password
    $lblConf = New-Object System.Windows.Forms.Label
    $lblConf.Text = "Confirm password:"
    $lblConf.Location = New-Object System.Drawing.Point(24, 300)
    $lblConf.AutoSize = $true
    $dlg.Controls.Add($lblConf)

    $txtConf = New-Object System.Windows.Forms.TextBox
    $txtConf.Location = New-Object System.Drawing.Point(24, 322)
    $txtConf.Size = New-Object System.Drawing.Size(476, 26)
    $txtConf.PasswordChar = [char]0x25CF
    $txtConf.BackColor = $Script:Theme.InputBg
    $txtConf.ForeColor = $Script:Theme.TextPrimary
    $txtConf.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $dlg.Controls.Add($txtConf)

    # Account Options Checkboxes
    $chkMustChange = New-Object System.Windows.Forms.CheckBox
    $chkMustChange.Text = "User must change password at next logon"
    $chkMustChange.Location = New-Object System.Drawing.Point(24, 362)
    $chkMustChange.AutoSize = $true
    $chkMustChange.Checked = $true
    $dlg.Controls.Add($chkMustChange)

    $chkNeverExpires = New-Object System.Windows.Forms.CheckBox
    $chkNeverExpires.Text = "Password never expires"
    $chkNeverExpires.Location = New-Object System.Drawing.Point(24, 390)
    $chkNeverExpires.AutoSize = $true
    $dlg.Controls.Add($chkNeverExpires)

    $chkDisabled = New-Object System.Windows.Forms.CheckBox
    $chkDisabled.Text = "Account is disabled"
    $chkDisabled.Location = New-Object System.Drawing.Point(24, 418)
    $chkDisabled.AutoSize = $true
    $dlg.Controls.Add($chkDisabled)

    # Buttons
    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "Create User"
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $btnOk.Location = New-Object System.Drawing.Point(270, 480)
    $btnOk.Size = New-Object System.Drawing.Size(110, 36)
    $btnOk.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnOk.FlatAppearance.BorderColor = $Script:Theme.Accent
    $btnOk.BackColor = $Script:Theme.AccentDark
    $btnOk.ForeColor = [System.Drawing.Color]::White
    $btnOk.Font = $Script:FontSmallBold
    $dlg.Controls.Add($btnOk)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $btnCancel.Location = New-Object System.Drawing.Point(390, 480)
    $btnCancel.Size = New-Object System.Drawing.Size(110, 36)
    $btnCancel.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnCancel.FlatAppearance.BorderColor = $Script:Theme.Border
    $btnCancel.BackColor = $Script:Theme.SurfaceAlt
    $btnCancel.ForeColor = $Script:Theme.TextPrimary
    $dlg.Controls.Add($btnCancel)

    $dlg.AcceptButton = $btnOk
    $dlg.CancelButton = $btnCancel

    $res = $dlg.ShowDialog($Script:MainForm)
    if ($res -eq [System.Windows.Forms.DialogResult]::OK) {
        $sam = $txtSam.Text.Trim()
        $display = $txtDisplay.Text.Trim()
        if (-not $sam) {
            [System.Windows.Forms.MessageBox]::Show("sAMAccountName cannot be empty.", "Validation Error", "OK", "Warning")
            return
        }
        if ($txtPass.Text -ne $txtConf.Text) {
            [System.Windows.Forms.MessageBox]::Show("Passwords do not match.", "Validation Error", "OK", "Warning")
            return
        }

        if ($Script:IsLiveAD) {
            $secPass = ConvertTo-SecureString $txtPass.Text -AsPlainText -Force
            New-ADUser -Name $display -DisplayName $display -SamAccountName $sam -UserPrincipalName "$sam@$($Script:ActiveDomainName)" -Path $TargetContainerDN -AccountPassword $secPass -Enabled (-not $chkDisabled.Checked) -ChangePasswordAtLogon $chkMustChange.Checked -PasswordNeverExpires $chkNeverExpires.Checked
        } else {
            $null = $Script:DemoStore.Objects.Add([PSCustomObject]@{
                ObjectClass          = "user"
                Name                 = $display
                displayName          = $display
                givenName            = $txtFirst.Text.Trim()
                sn                   = $txtLast.Text.Trim()
                sAMAccountName       = $sam
                userPrincipalName    = "$sam@corp.contoso.local"
                mail                 = "$sam@corp.contoso.local"
                title                = "New Employee"
                department           = "Operations"
                company              = "Contoso Corp"
                office               = "HQ"
                telephoneNumber      = ""
                DistinguishedName    = "CN=$display,$TargetContainerDN"
                ParentDN             = $TargetContainerDN
                Description          = "New User created via ADUCK"
                Enabled              = (-not $chkDisabled.Checked)
                LockedOut            = $false
                PasswordLastSet      = (Get-Date).ToString("yyyy-MM-dd HH:mm")
                LastLogonDate        = ""
                PasswordNeverExpires = $chkNeverExpires.Checked
                MustChangePasswordAtNextLogon = $chkMustChange.Checked
                CannotChangePassword = $false
                AccountExpires       = $null
                whenCreated          = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                whenChanged          = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                MemberOf             = @("All-Employees")
            })
        }
        Set-StatusMessage "User '$display' created successfully."
        Refresh-CurrentContainerView
    }
}

# Dialog: New Group
function Show-NewGroupDialog {
    param([string]$TargetContainerDN)

    $dlg = New-ModernDialog -Title "Create New Active Directory Group" -Width 480 -Height 420

    $lblHdr = New-Object System.Windows.Forms.Label
    $lblHdr.Text = "New Security / Distribution Group"
    $lblHdr.Font = $Script:FontTitle
    $lblHdr.Location = New-Object System.Drawing.Point(24, 20)
    $lblHdr.AutoSize = $true
    $dlg.Controls.Add($lblHdr)

    # Group Name
    $lblName = New-Object System.Windows.Forms.Label
    $lblName.Text = "Group name:"
    $lblName.Location = New-Object System.Drawing.Point(24, 60)
    $lblName.AutoSize = $true
    $dlg.Controls.Add($lblName)

    $txtName = New-Object System.Windows.Forms.TextBox
    $txtName.Location = New-Object System.Drawing.Point(24, 82)
    $txtName.Size = New-Object System.Drawing.Size(416, 26)
    $txtName.BackColor = $Script:Theme.InputBg
    $txtName.ForeColor = $Script:Theme.TextPrimary
    $txtName.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $dlg.Controls.Add($txtName)

    # Description
    $lblDesc = New-Object System.Windows.Forms.Label
    $lblDesc.Text = "Description:"
    $lblDesc.Location = New-Object System.Drawing.Point(24, 120)
    $lblDesc.AutoSize = $true
    $dlg.Controls.Add($lblDesc)

    $txtDesc = New-Object System.Windows.Forms.TextBox
    $txtDesc.Location = New-Object System.Drawing.Point(24, 142)
    $txtDesc.Size = New-Object System.Drawing.Size(416, 26)
    $txtDesc.BackColor = $Script:Theme.InputBg
    $txtDesc.ForeColor = $Script:Theme.TextPrimary
    $txtDesc.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $dlg.Controls.Add($txtDesc)

    # Group Scope
    $grpScope = New-Object System.Windows.Forms.GroupBox
    $grpScope.Text = "Group scope"
    $grpScope.Location = New-Object System.Drawing.Point(24, 180)
    $grpScope.Size = New-Object System.Drawing.Size(200, 110)
    $grpScope.ForeColor = $Script:Theme.TextPrimary
    $dlg.Controls.Add($grpScope)

    $rdoLocal = New-Object System.Windows.Forms.RadioButton
    $rdoLocal.Text = "Domain local"; $rdoLocal.Location = New-Object System.Drawing.Point(12, 22); $rdoLocal.AutoSize = $true
    $rdoGlobal = New-Object System.Windows.Forms.RadioButton
    $rdoGlobal.Text = "Global"; $rdoGlobal.Location = New-Object System.Drawing.Point(12, 48); $rdoGlobal.AutoSize = $true; $rdoGlobal.Checked = $true
    $rdoUniv = New-Object System.Windows.Forms.RadioButton
    $rdoUniv.Text = "Universal"; $rdoUniv.Location = New-Object System.Drawing.Point(12, 74); $rdoUniv.AutoSize = $true
    $grpScope.Controls.AddRange(@($rdoLocal, $rdoGlobal, $rdoUniv))

    # Group Type
    $grpType = New-Object System.Windows.Forms.GroupBox
    $grpType.Text = "Group type"
    $grpType.Location = New-Object System.Drawing.Point(240, 180)
    $grpType.Size = New-Object System.Drawing.Size(200, 110)
    $grpType.ForeColor = $Script:Theme.TextPrimary
    $dlg.Controls.Add($grpType)

    $rdoSec = New-Object System.Windows.Forms.RadioButton
    $rdoSec.Text = "Security"; $rdoSec.Location = New-Object System.Drawing.Point(12, 26); $rdoSec.AutoSize = $true; $rdoSec.Checked = $true
    $rdoDist = New-Object System.Windows.Forms.RadioButton
    $rdoDist.Text = "Distribution"; $rdoDist.Location = New-Object System.Drawing.Point(12, 58); $rdoDist.AutoSize = $true
    $grpType.Controls.AddRange(@($rdoSec, $rdoDist))

    # Buttons
    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "Create Group"
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $btnOk.Location = New-Object System.Drawing.Point(210, 320)
    $btnOk.Size = New-Object System.Drawing.Size(110, 34)
    $btnOk.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnOk.FlatAppearance.BorderColor = $Script:Theme.Accent
    $btnOk.BackColor = $Script:Theme.AccentDark
    $btnOk.ForeColor = [System.Drawing.Color]::White
    $dlg.Controls.Add($btnOk)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $btnCancel.Location = New-Object System.Drawing.Point(330, 320)
    $btnCancel.Size = New-Object System.Drawing.Size(110, 34)
    $btnCancel.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnCancel.FlatAppearance.BorderColor = $Script:Theme.Border
    $btnCancel.BackColor = $Script:Theme.SurfaceAlt
    $btnCancel.ForeColor = $Script:Theme.TextPrimary
    $dlg.Controls.Add($btnCancel)

    $dlg.AcceptButton = $btnOk
    $dlg.CancelButton = $btnCancel

    $res = $dlg.ShowDialog($Script:MainForm)
    if ($res -eq [System.Windows.Forms.DialogResult]::OK) {
        $name = $txtName.Text.Trim()
        if (-not $name) { return }
        $scope = if ($rdoLocal.Checked) { "DomainLocal" } elseif ($rdoUniv.Checked) { "Universal" } else { "Global" }
        $category = if ($rdoDist.Checked) { "Distribution" } else { "Security" }

        if ($Script:IsLiveAD) {
            New-ADGroup -Name $name -GroupScope $scope -GroupCategory $category -Path $TargetContainerDN -Description $txtDesc.Text.Trim()
        } else {
            $null = $Script:DemoStore.Objects.Add([PSCustomObject]@{
                ObjectClass       = "group"
                Name              = $name
                sAMAccountName    = $name
                DistinguishedName = "CN=$name,$TargetContainerDN"
                ParentDN          = $TargetContainerDN
                Description       = $txtDesc.Text.Trim()
                GroupScope        = $scope
                GroupType         = $category
                Enabled           = $true
                LockedOut         = $false
                whenCreated       = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                whenChanged       = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                MemberOf          = @()
            })
        }
        Set-StatusMessage "Group '$name' created successfully."
        Refresh-CurrentContainerView
    }
}

# Dialog: New Computer
function Show-NewComputerDialog {
    param([string]$TargetContainerDN)

    $dlg = New-ModernDialog -Title "Create New Active Directory Computer" -Width 480 -Height 300

    $lblHdr = New-Object System.Windows.Forms.Label
    $lblHdr.Text = "New Computer Account"
    $lblHdr.Font = $Script:FontTitle
    $lblHdr.Location = New-Object System.Drawing.Point(24, 20)
    $lblHdr.AutoSize = $true
    $dlg.Controls.Add($lblHdr)

    # Computer Name
    $lblName = New-Object System.Windows.Forms.Label
    $lblName.Text = "Computer name:"
    $lblName.Location = New-Object System.Drawing.Point(24, 60)
    $lblName.AutoSize = $true
    $dlg.Controls.Add($lblName)

    $txtName = New-Object System.Windows.Forms.TextBox
    $txtName.Location = New-Object System.Drawing.Point(24, 82)
    $txtName.Size = New-Object System.Drawing.Size(416, 26)
    $txtName.BackColor = $Script:Theme.InputBg
    $txtName.ForeColor = $Script:Theme.TextPrimary
    $txtName.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $dlg.Controls.Add($txtName)

    # Description
    $lblDesc = New-Object System.Windows.Forms.Label
    $lblDesc.Text = "Description:"
    $lblDesc.Location = New-Object System.Drawing.Point(24, 120)
    $lblDesc.AutoSize = $true
    $dlg.Controls.Add($lblDesc)

    $txtDesc = New-Object System.Windows.Forms.TextBox
    $txtDesc.Location = New-Object System.Drawing.Point(24, 142)
    $txtDesc.Size = New-Object System.Drawing.Size(416, 26)
    $txtDesc.BackColor = $Script:Theme.InputBg
    $txtDesc.ForeColor = $Script:Theme.TextPrimary
    $txtDesc.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $dlg.Controls.Add($txtDesc)

    # Buttons
    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "Create Computer"
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $btnOk.Location = New-Object System.Drawing.Point(190, 200)
    $btnOk.Size = New-Object System.Drawing.Size(130, 34)
    $btnOk.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnOk.FlatAppearance.BorderColor = $Script:Theme.Accent
    $btnOk.BackColor = $Script:Theme.AccentDark
    $btnOk.ForeColor = [System.Drawing.Color]::White
    $dlg.Controls.Add($btnOk)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $btnCancel.Location = New-Object System.Drawing.Point(330, 200)
    $btnCancel.Size = New-Object System.Drawing.Size(110, 34)
    $btnCancel.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnCancel.FlatAppearance.BorderColor = $Script:Theme.Border
    $btnCancel.BackColor = $Script:Theme.SurfaceAlt
    $btnCancel.ForeColor = $Script:Theme.TextPrimary
    $dlg.Controls.Add($btnCancel)

    $dlg.AcceptButton = $btnOk
    $dlg.CancelButton = $btnCancel

    $res = $dlg.ShowDialog($Script:MainForm)
    if ($res -eq [System.Windows.Forms.DialogResult]::OK) {
        $name = $txtName.Text.Trim()
        if (-not $name) { return }
        if ($Script:IsLiveAD) {
            New-ADComputer -Name $name -Path $TargetContainerDN -Description $txtDesc.Text.Trim()
        } else {
            $null = $Script:DemoStore.Objects.Add([PSCustomObject]@{
                ObjectClass       = "computer"
                Name              = $name
                sAMAccountName    = "$name$"
                DistinguishedName = "CN=$name,$TargetContainerDN"
                ParentDN          = $TargetContainerDN
                Description       = $txtDesc.Text.Trim()
                OperatingSystem   = "Windows 11 Enterprise"
                Enabled           = $true
                LockedOut         = $false
                whenCreated       = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                whenChanged       = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                MemberOf          = @("Domain Computers")
            })
        }
        Set-StatusMessage "Computer '$name' created successfully."
        Refresh-CurrentContainerView
    }
}

# Dialog: New OU
function Show-NewOUDialog {
    param([string]$TargetContainerDN)

    $dlg = New-ModernDialog -Title "Create New Organizational Unit" -Width 480 -Height 280

    $lblHdr = New-Object System.Windows.Forms.Label
    $lblHdr.Text = "New Organizational Unit"
    $lblHdr.Font = $Script:FontTitle
    $lblHdr.Location = New-Object System.Drawing.Point(24, 20)
    $lblHdr.AutoSize = $true
    $dlg.Controls.Add($lblHdr)

    # Name
    $lblName = New-Object System.Windows.Forms.Label
    $lblName.Text = "Name:"
    $lblName.Location = New-Object System.Drawing.Point(24, 60)
    $lblName.AutoSize = $true
    $dlg.Controls.Add($lblName)

    $txtName = New-Object System.Windows.Forms.TextBox
    $txtName.Location = New-Object System.Drawing.Point(24, 82)
    $txtName.Size = New-Object System.Drawing.Size(416, 26)
    $txtName.BackColor = $Script:Theme.InputBg
    $txtName.ForeColor = $Script:Theme.TextPrimary
    $txtName.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $dlg.Controls.Add($txtName)

    $chkProtect = New-Object System.Windows.Forms.CheckBox
    $chkProtect.Text = "Protect container from accidental deletion"
    $chkProtect.Location = New-Object System.Drawing.Point(24, 120)
    $chkProtect.AutoSize = $true
    $chkProtect.Checked = $true
    $dlg.Controls.Add($chkProtect)

    # Buttons
    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "Create OU"
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $btnOk.Location = New-Object System.Drawing.Point(210, 180)
    $btnOk.Size = New-Object System.Drawing.Size(110, 34)
    $btnOk.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnOk.FlatAppearance.BorderColor = $Script:Theme.Accent
    $btnOk.BackColor = $Script:Theme.AccentDark
    $btnOk.ForeColor = [System.Drawing.Color]::White
    $dlg.Controls.Add($btnOk)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $btnCancel.Location = New-Object System.Drawing.Point(330, 180)
    $btnCancel.Size = New-Object System.Drawing.Size(110, 34)
    $btnCancel.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnCancel.FlatAppearance.BorderColor = $Script:Theme.Border
    $btnCancel.BackColor = $Script:Theme.SurfaceAlt
    $btnCancel.ForeColor = $Script:Theme.TextPrimary
    $dlg.Controls.Add($btnCancel)

    $dlg.AcceptButton = $btnOk
    $dlg.CancelButton = $btnCancel

    $res = $dlg.ShowDialog($Script:MainForm)
    if ($res -eq [System.Windows.Forms.DialogResult]::OK) {
        $name = $txtName.Text.Trim()
        if (-not $name) { return }
        if ($Script:IsLiveAD) {
            New-ADOrganizationalUnit -Name $name -Path $TargetContainerDN -ProtectedFromAccidentalDeletion $chkProtect.Checked
        } else {
            $newDN = "OU=$name,$TargetContainerDN"
            $Script:DemoStore.Containers += [PSCustomObject]@{
                Name              = $name
                DistinguishedName = $newDN
                Type              = "ou"
                ParentDN          = $TargetContainerDN
            }
        }
        Set-StatusMessage "Organizational Unit '$name' created."
        Populate-DirectoryTree
    }
}

# Dialog: Reset Password
function Show-ResetPasswordDialog {
    param($UserObject)

    $dlg = New-ModernDialog -Title "Reset Password - $($UserObject.displayName)" -Width 480 -Height 360

    $lblHdr = New-Object System.Windows.Forms.Label
    $lblHdr.Text = "Reset Password"
    $lblHdr.Font = $Script:FontTitle
    $lblHdr.Location = New-Object System.Drawing.Point(24, 20)
    $lblHdr.AutoSize = $true
    $dlg.Controls.Add($lblHdr)

    $lblUser = New-Object System.Windows.Forms.Label
    $lblUser.Text = "User: $($UserObject.displayName) ($($UserObject.sAMAccountName))"
    $lblUser.Font = $Script:FontSmall
    $lblUser.ForeColor = $Script:Theme.TextSecondary
    $lblUser.Location = New-Object System.Drawing.Point(26, 46)
    $lblUser.AutoSize = $true
    $dlg.Controls.Add($lblUser)

    # New Password
    $lblPass = New-Object System.Windows.Forms.Label
    $lblPass.Text = "New password:"
    $lblPass.Location = New-Object System.Drawing.Point(24, 80)
    $lblPass.AutoSize = $true
    $dlg.Controls.Add($lblPass)

    $txtPass = New-Object System.Windows.Forms.TextBox
    $txtPass.Location = New-Object System.Drawing.Point(24, 102)
    $txtPass.Size = New-Object System.Drawing.Size(416, 26)
    $txtPass.PasswordChar = [char]0x25CF
    $txtPass.BackColor = $Script:Theme.InputBg
    $txtPass.ForeColor = $Script:Theme.TextPrimary
    $txtPass.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $dlg.Controls.Add($txtPass)

    # Confirm Password
    $lblConf = New-Object System.Windows.Forms.Label
    $lblConf.Text = "Confirm password:"
    $lblConf.Location = New-Object System.Drawing.Point(24, 140)
    $lblConf.AutoSize = $true
    $dlg.Controls.Add($lblConf)

    $txtConf = New-Object System.Windows.Forms.TextBox
    $txtConf.Location = New-Object System.Drawing.Point(24, 162)
    $txtConf.Size = New-Object System.Drawing.Size(416, 26)
    $txtConf.PasswordChar = [char]0x25CF
    $txtConf.BackColor = $Script:Theme.InputBg
    $txtConf.ForeColor = $Script:Theme.TextPrimary
    $txtConf.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $dlg.Controls.Add($txtConf)

    # Checkboxes
    $chkMustChange = New-Object System.Windows.Forms.CheckBox
    $chkMustChange.Text = "User must change password at next logon"
    $chkMustChange.Location = New-Object System.Drawing.Point(24, 202)
    $chkMustChange.AutoSize = $true
    $chkMustChange.Checked = $true
    $dlg.Controls.Add($chkMustChange)

    $chkUnlock = New-Object System.Windows.Forms.CheckBox
    $chkUnlock.Text = "Unlock user's account"
    $chkUnlock.Location = New-Object System.Drawing.Point(24, 230)
    $chkUnlock.AutoSize = $true
    $chkUnlock.Checked = [bool]$UserObject.LockedOut
    $dlg.Controls.Add($chkUnlock)

    # Buttons
    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "Reset Password"
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $btnOk.Location = New-Object System.Drawing.Point(180, 270)
    $btnOk.Size = New-Object System.Drawing.Size(140, 34)
    $btnOk.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnOk.FlatAppearance.BorderColor = $Script:Theme.Accent
    $btnOk.BackColor = $Script:Theme.AccentDark
    $btnOk.ForeColor = [System.Drawing.Color]::White
    $dlg.Controls.Add($btnOk)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $btnCancel.Location = New-Object System.Drawing.Point(330, 270)
    $btnCancel.Size = New-Object System.Drawing.Size(110, 34)
    $btnCancel.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnCancel.FlatAppearance.BorderColor = $Script:Theme.Border
    $btnCancel.BackColor = $Script:Theme.SurfaceAlt
    $btnCancel.ForeColor = $Script:Theme.TextPrimary
    $dlg.Controls.Add($btnCancel)

    $dlg.AcceptButton = $btnOk
    $dlg.CancelButton = $btnCancel

    $res = $dlg.ShowDialog($Script:MainForm)
    if ($res -eq [System.Windows.Forms.DialogResult]::OK) {
        if (-not $txtPass.Text) {
            [System.Windows.Forms.MessageBox]::Show("Password cannot be blank.", "Validation Error", "OK", "Warning")
            return
        }
        if ($txtPass.Text -ne $txtConf.Text) {
            [System.Windows.Forms.MessageBox]::Show("Passwords do not match.", "Validation Error", "OK", "Warning")
            return
        }
        $secPass = ConvertTo-SecureString $txtPass.Text -AsPlainText -Force
        Set-ADUserPasswordReset -DistinguishedName $UserObject.DistinguishedName -Password $secPass -MustChangeAtNextLogon $chkMustChange.Checked -Unlock $chkUnlock.Checked
        Set-StatusMessage "Password reset successfully for $($UserObject.displayName)."
        Refresh-CurrentContainerView
    }
}

# Dialog: Move Object
function Show-MoveObjectDialog {
    param($DirectoryObject)

    $dlg = New-ModernDialog -Title "Move Object - $($DirectoryObject.Name)" -Width 500 -Height 480

    $lblHdr = New-Object System.Windows.Forms.Label
    $lblHdr.Text = "Select Destination Container or OU:"
    $lblHdr.Font = $Script:FontTitle
    $lblHdr.Location = New-Object System.Drawing.Point(20, 16)
    $lblHdr.AutoSize = $true
    $dlg.Controls.Add($lblHdr)

    # Destination Tree
    $destTree = New-Object System.Windows.Forms.TreeView
    $destTree.Location = New-Object System.Drawing.Point(20, 50)
    $destTree.Size = New-Object System.Drawing.Size(444, 330)
    $destTree.BackColor = $Script:Theme.InputBg
    $destTree.ForeColor = $Script:Theme.TextPrimary
    $destTree.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $destTree.ImageList = $Script:ImageList
    $destTree.FullRowSelect = $true
    $dlg.Controls.Add($destTree)

    # Populate destination tree
    $root = Get-ADRootInformation
    $rootNode = $destTree.Nodes.Add($root.DistinguishedName, $root.Name, "domain", "domain")
    $rootNode.Tag = $root.DistinguishedName

    $containers = Get-ADTreeHierarchy
    $nodeMap = @{ $root.DistinguishedName = $rootNode }

    foreach ($c in $containers) {
        $parent = $nodeMap[$c.ParentDN]
        if (-not $parent) { $parent = $rootNode }
        $icon = if ($c.Type -eq 'ou') { "ou" } else { "container" }
        $newNode = $parent.Nodes.Add($c.DistinguishedName, $c.Name, $icon, $icon)
        $newNode.Tag = $c.DistinguishedName
        $nodeMap[$c.DistinguishedName] = $newNode
    }
    $rootNode.Expand()

    # Buttons
    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "Move Here"
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $btnOk.Location = New-Object System.Drawing.Point(230, 395)
    $btnOk.Size = New-Object System.Drawing.Size(110, 34)
    $btnOk.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnOk.FlatAppearance.BorderColor = $Script:Theme.Accent
    $btnOk.BackColor = $Script:Theme.AccentDark
    $btnOk.ForeColor = [System.Drawing.Color]::White
    $dlg.Controls.Add($btnOk)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $btnCancel.Location = New-Object System.Drawing.Point(354, 395)
    $btnCancel.Size = New-Object System.Drawing.Size(110, 34)
    $btnCancel.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnCancel.FlatAppearance.BorderColor = $Script:Theme.Border
    $btnCancel.BackColor = $Script:Theme.SurfaceAlt
    $btnCancel.ForeColor = $Script:Theme.TextPrimary
    $dlg.Controls.Add($btnCancel)

    $dlg.AcceptButton = $btnOk
    $dlg.CancelButton = $btnCancel

    $res = $dlg.ShowDialog($Script:MainForm)
    if ($res -eq [System.Windows.Forms.DialogResult]::OK) {
        if ($destTree.SelectedNode) {
            $targetDN = $destTree.SelectedNode.Tag
            Move-ADDirectoryObject -DistinguishedName $DirectoryObject.DistinguishedName -TargetContainerDN $targetDN
            Set-StatusMessage "Moved '$($DirectoryObject.Name)' to target container."
            Refresh-CurrentContainerView
        }
    }
}

# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
# Dialog: Delegate Control Wizard
# -----------------------------------------------------------------------------
function Show-DelegateControlDialog {
    param([string]$TargetContainerDN)

    if (-not $TargetContainerDN) {
        $TargetContainerDN = if ($treeView.SelectedNode) { $treeView.SelectedNode.Tag } else { $Script:RootInfo.DistinguishedName }
    }

    $dlg = New-ModernDialog -Title "Delegation of Control Wizard" -Width 580 -Height 580

    # Header Panel
    $pnlHdr = New-Object System.Windows.Forms.Panel
    $pnlHdr.Location = New-Object System.Drawing.Point(0, 0)
    $pnlHdr.Size = New-Object System.Drawing.Size(580, 68)
    $pnlHdr.BackColor = $Script:Theme.SurfaceAlt
    $dlg.Controls.Add($pnlHdr)

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "Delegation of Control"
    $lblTitle.Font = $Script:FontTitle
    $lblTitle.ForeColor = $Script:Theme.TextPrimary
    $lblTitle.Location = New-Object System.Drawing.Point(20, 12)
    $lblTitle.AutoSize = $true
    $pnlHdr.Controls.Add($lblTitle)

    $lblSub = New-Object System.Windows.Forms.Label
    $lblSub.Text = "Delegate administrative tasks on: $TargetContainerDN"
    $lblSub.Font = $Script:FontSmall
    $lblSub.ForeColor = $Script:Theme.TextSecondary
    $lblSub.Location = New-Object System.Drawing.Point(22, 38)
    $lblSub.Size = New-Object System.Drawing.Size(540, 20)
    $lblSub.AutoEllipsis = $true
    $pnlHdr.Controls.Add($lblSub)

    # 1. Users or Groups selection
    $lblUsers = New-Object System.Windows.Forms.Label
    $lblUsers.Text = "Selected Users or Groups:"
    $lblUsers.Font = $Script:FontBodyBold
    $lblUsers.ForeColor = $Script:Theme.TextPrimary
    $lblUsers.Location = New-Object System.Drawing.Point(20, 80)
    $lblUsers.AutoSize = $true
    $dlg.Controls.Add($lblUsers)

    $lstUsers = New-Object System.Windows.Forms.ListBox
    $lstUsers.Location = New-Object System.Drawing.Point(20, 105)
    $lstUsers.Size = New-Object System.Drawing.Size(420, 95)
    $lstUsers.BackColor = $Script:Theme.InputBg
    $lstUsers.ForeColor = $Script:Theme.TextPrimary
    $lstUsers.Font = $Script:FontBody
    $lstUsers.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    [void]$lstUsers.Items.Add("IT-Admins (CORP\IT-Admins)")
    $dlg.Controls.Add($lstUsers)

    $btnAddUser = New-Object ADUCK.DarkButton
    $btnAddUser.Text = "Add..."
    $btnAddUser.Location = New-Object System.Drawing.Point(450, 105)
    $btnAddUser.Size = New-Object System.Drawing.Size(95, 30)
    $btnAddUser.Font = $Script:FontSmallBold
    $dlg.Controls.Add($btnAddUser)

    $btnRemUser = New-Object ADUCK.DarkButton
    $btnRemUser.Text = "Remove"
    $btnRemUser.Location = New-Object System.Drawing.Point(450, 142)
    $btnRemUser.Size = New-Object System.Drawing.Size(95, 30)
    $btnRemUser.Font = $Script:FontSmallBold
    $dlg.Controls.Add($btnRemUser)

    $btnAddUser.Add_Click({
        Add-Type -AssemblyName Microsoft.VisualBasic
        $name = [Microsoft.VisualBasic.Interaction]::InputBox("Enter user or group name to delegate control to:", "Add Principal", "Helpdesk")
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            [void]$lstUsers.Items.Add($name.Trim())
        }
    })

    $btnRemUser.Add_Click({
        if ($lstUsers.SelectedIndex -ge 0) {
            $lstUsers.Items.RemoveAt($lstUsers.SelectedIndex)
        }
    })

    # 2. Tasks to delegate
    $lblTasks = New-Object System.Windows.Forms.Label
    $lblTasks.Text = "Tasks to delegate:"
    $lblTasks.Font = $Script:FontBodyBold
    $lblTasks.ForeColor = $Script:Theme.TextPrimary
    $lblTasks.Location = New-Object System.Drawing.Point(20, 215)
    $lblTasks.AutoSize = $true
    $dlg.Controls.Add($lblTasks)

    $chkTasks = New-Object System.Windows.Forms.CheckedListBox
    $chkTasks.Location = New-Object System.Drawing.Point(20, 240)
    $chkTasks.Size = New-Object System.Drawing.Size(525, 210)
    $chkTasks.BackColor = $Script:Theme.InputBg
    $chkTasks.ForeColor = $Script:Theme.TextPrimary
    $chkTasks.Font = $Script:FontBody
    $chkTasks.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $chkTasks.CheckOnClick = $true

    $standardTasks = @(
        "Create, delete, and manage user accounts",
        "Reset user passwords and force password change at next logon",
        "Read all user information",
        "Create, delete and manage groups",
        "Modify the membership of a group",
        "Join a computer to the domain",
        "Manage Group Policy links",
        "Generate Resultant Set of Policy (Planning)",
        "Generate Resultant Set of Policy (Logging)"
    )
    foreach ($t in $standardTasks) {
        [void]$chkTasks.Items.Add($t)
    }
    $chkTasks.SetItemChecked(0, $true)
    $chkTasks.SetItemChecked(1, $true)
    $dlg.Controls.Add($chkTasks)

    # Buttons
    $btnDelegate = New-Object ADUCK.DarkButton
    $btnDelegate.Text = "Delegate Control"
    $btnDelegate.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $btnDelegate.Location = New-Object System.Drawing.Point(275, 480)
    $btnDelegate.Size = New-Object System.Drawing.Size(140, 36)
    $btnDelegate.Font = $Script:FontSmallBold
    $btnDelegate.NormalBackColor = $Script:Theme.AccentDark
    $btnDelegate.NormalForeColor = [System.Drawing.Color]::White
    $btnDelegate.NormalBorderColor = $Script:Theme.Accent
    $btnDelegate.HoverBackColor = $Script:Theme.AccentHover
    $btnDelegate.HoverBorderColor = $Script:Theme.Accent
    $dlg.Controls.Add($btnDelegate)

    $btnCancel = New-Object ADUCK.DarkButton
    $btnCancel.Text = "Cancel"
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $btnCancel.Location = New-Object System.Drawing.Point(425, 480)
    $btnCancel.Size = New-Object System.Drawing.Size(120, 36)
    $btnCancel.Font = $Script:FontSmallBold
    $dlg.Controls.Add($btnCancel)

    $dlg.AcceptButton = $btnDelegate
    $dlg.CancelButton = $btnCancel

    if ($dlg.ShowDialog($Script:MainForm) -eq [System.Windows.Forms.DialogResult]::OK) {
        $selectedPrincipals = @($lstUsers.Items)
        $selectedTasksList = @()
        for ($i = 0; $i -lt $chkTasks.Items.Count; $i++) {
            if ($chkTasks.GetItemChecked($i)) {
                $selectedTasksList += $chkTasks.Items[$i]
            }
        }
        Invoke-ADDelegateControl -TargetContainerDN $TargetContainerDN -Principals $selectedPrincipals -SelectedTasks $selectedTasksList
        [System.Windows.Forms.MessageBox]::Show(
            "Delegation of control completed successfully on:`n$TargetContainerDN`n`nDelegated to: $($selectedPrincipals -join ', ')`nTasks assigned: $($selectedTasksList.Count)",
            "Delegation Successful",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
    }
}

# -----------------------------------------------------------------------------
# Dialog: Change Domain
# -----------------------------------------------------------------------------
function Show-ChangeDomainDialog {
    $currentRoot = Get-ADRootInformation
    $dlg = New-ModernDialog -Title "Change Domain" -Width 480 -Height 360

    # Header
    $pnlHdr = New-Object System.Windows.Forms.Panel
    $pnlHdr.Location = New-Object System.Drawing.Point(0, 0)
    $pnlHdr.Size = New-Object System.Drawing.Size(480, 60)
    $pnlHdr.BackColor = $Script:Theme.SurfaceAlt
    $dlg.Controls.Add($pnlHdr)

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "Change Active Directory Domain"
    $lblTitle.Font = $Script:FontTitle
    $lblTitle.ForeColor = $Script:Theme.TextPrimary
    $lblTitle.Location = New-Object System.Drawing.Point(20, 12)
    $lblTitle.AutoSize = $true
    $pnlHdr.Controls.Add($lblTitle)

    $lblSub = New-Object System.Windows.Forms.Label
    $lblSub.Text = "Current Domain: $($currentRoot.Name) ($($currentRoot.Mode))"
    $lblSub.Font = $Script:FontSmall
    $lblSub.ForeColor = $Script:Theme.TextSecondary
    $lblSub.Location = New-Object System.Drawing.Point(22, 34)
    $lblSub.AutoSize = $true
    $pnlHdr.Controls.Add($lblSub)

    # Domain Input
    $lblDom = New-Object System.Windows.Forms.Label
    $lblDom.Text = "Target Domain Name:"
    $lblDom.Font = $Script:FontBodyBold
    $lblDom.ForeColor = $Script:Theme.TextPrimary
    $lblDom.Location = New-Object System.Drawing.Point(20, 80)
    $lblDom.AutoSize = $true
    $dlg.Controls.Add($lblDom)

    $txtDom = New-Object System.Windows.Forms.TextBox
    $txtDom.Text = $currentRoot.Name
    $txtDom.Location = New-Object System.Drawing.Point(20, 105)
    $txtDom.Size = New-Object System.Drawing.Size(425, 28)
    $txtDom.BackColor = $Script:Theme.InputBg
    $txtDom.ForeColor = $Script:Theme.TextPrimary
    $txtDom.Font = $Script:FontBody
    $txtDom.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $dlg.Controls.Add($txtDom)

    # Suggested Domains Dropdown
    $lblSug = New-Object System.Windows.Forms.Label
    $lblSug.Text = "Available Domains in Forest:"
    $lblSug.Font = $Script:FontSmall
    $lblSug.ForeColor = $Script:Theme.TextSecondary
    $lblSug.Location = New-Object System.Drawing.Point(20, 145)
    $lblSug.AutoSize = $true
    $dlg.Controls.Add($lblSug)

    $cboDom = New-Object System.Windows.Forms.ComboBox
    $cboDom.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $cboDom.Location = New-Object System.Drawing.Point(20, 170)
    $cboDom.Size = New-Object System.Drawing.Size(425, 28)
    $cboDom.BackColor = $Script:Theme.InputBg
    $cboDom.ForeColor = $Script:Theme.TextPrimary
    $cboDom.Font = $Script:FontBody
    $cboDom.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $knownDomains = @("CORP.CONTOSO.LOCAL", "SALES.CONTOSO.LOCAL", "DEV.CONTOSO.LOCAL", "CONTOSO.COM")
    foreach ($kd in $knownDomains) { [void]$cboDom.Items.Add($kd) }
    $cboDom.SelectedItem = $currentRoot.Name
    $cboDom.Add_SelectedIndexChanged({
        if ($cboDom.SelectedItem) { $txtDom.Text = $cboDom.SelectedItem }
    })
    $dlg.Controls.Add($cboDom)

    $chkSave = New-Object System.Windows.Forms.CheckBox
    $chkSave.Text = "Save this domain setting for the current console"
    $chkSave.Checked = $true
    $chkSave.Location = New-Object System.Drawing.Point(20, 215)
    $chkSave.Size = New-Object System.Drawing.Size(425, 24)
    $chkSave.ForeColor = $Script:Theme.TextPrimary
    $chkSave.Font = $Script:FontSmall
    $dlg.Controls.Add($chkSave)

    # Buttons
    $btnConnect = New-Object ADUCK.DarkButton
    $btnConnect.Text = "Connect"
    $btnConnect.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $btnConnect.Location = New-Object System.Drawing.Point(215, 260)
    $btnConnect.Size = New-Object System.Drawing.Size(110, 36)
    $btnConnect.Font = $Script:FontSmallBold
    $btnConnect.NormalBackColor = $Script:Theme.AccentDark
    $btnConnect.NormalForeColor = [System.Drawing.Color]::White
    $btnConnect.NormalBorderColor = $Script:Theme.Accent
    $btnConnect.HoverBackColor = $Script:Theme.AccentHover
    $btnConnect.HoverBorderColor = $Script:Theme.Accent
    $dlg.Controls.Add($btnConnect)

    $btnCancel = New-Object ADUCK.DarkButton
    $btnCancel.Text = "Cancel"
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $btnCancel.Location = New-Object System.Drawing.Point(335, 260)
    $btnCancel.Size = New-Object System.Drawing.Size(110, 36)
    $btnCancel.Font = $Script:FontSmallBold
    $dlg.Controls.Add($btnCancel)

    $dlg.AcceptButton = $btnConnect
    $dlg.CancelButton = $btnCancel

    if ($dlg.ShowDialog($Script:MainForm) -eq [System.Windows.Forms.DialogResult]::OK) {
        $targetDomain = $txtDom.Text.Trim()
        if (-not [string]::IsNullOrWhiteSpace($targetDomain)) {
            Switch-ADTargetDomain -NewDomainName $targetDomain
        }
    }
}

# -----------------------------------------------------------------------------
# Dialog: Change Directory Server (Domain Controller)
# -----------------------------------------------------------------------------
function Show-ChangeDomainControllerDialog {
    $currentRoot = Get-ADRootInformation
    $dlg = New-ModernDialog -Title "Change Directory Server" -Width 520 -Height 450

    # Header
    $pnlHdr = New-Object System.Windows.Forms.Panel
    $pnlHdr.Location = New-Object System.Drawing.Point(0, 0)
    $pnlHdr.Size = New-Object System.Drawing.Size(520, 60)
    $pnlHdr.BackColor = $Script:Theme.SurfaceAlt
    $dlg.Controls.Add($pnlHdr)

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "Change Directory Server"
    $lblTitle.Font = $Script:FontTitle
    $lblTitle.ForeColor = $Script:Theme.TextPrimary
    $lblTitle.Location = New-Object System.Drawing.Point(20, 12)
    $lblTitle.AutoSize = $true
    $pnlHdr.Controls.Add($lblTitle)

    $lblSub = New-Object System.Windows.Forms.Label
    $lblSub.Text = "Domain: $($currentRoot.Name) - Current DC: $($currentRoot.PDCEmulator)"
    $lblSub.Font = $Script:FontSmall
    $lblSub.ForeColor = $Script:Theme.TextSecondary
    $lblSub.Location = New-Object System.Drawing.Point(22, 34)
    $lblSub.AutoSize = $true
    $pnlHdr.Controls.Add($lblSub)

    # Radio 1: Any Writable DC
    $rbAny = New-Object System.Windows.Forms.RadioButton
    $rbAny.Text = "Any writable Domain Controller (Auto-discover)"
    $rbAny.Location = New-Object System.Drawing.Point(20, 75)
    $rbAny.Size = New-Object System.Drawing.Size(460, 24)
    $rbAny.ForeColor = $Script:Theme.TextPrimary
    $rbAny.Font = $Script:FontBody
    $dlg.Controls.Add($rbAny)

    # Radio 2: This DC
    $rbThis = New-Object System.Windows.Forms.RadioButton
    $rbThis.Text = "This Domain Controller:"
    $rbThis.Checked = $true
    $rbThis.Location = New-Object System.Drawing.Point(20, 105)
    $rbThis.Size = New-Object System.Drawing.Size(460, 24)
    $rbThis.ForeColor = $Script:Theme.TextPrimary
    $rbThis.Font = $Script:FontBodyBold
    $dlg.Controls.Add($rbThis)

    # ListView of DCs
    $lvwDCs = New-Object System.Windows.Forms.ListView
    $lvwDCs.View = [System.Windows.Forms.View]::Details
    $lvwDCs.FullRowSelect = $true
    $lvwDCs.MultiSelect = $false
    $lvwDCs.Location = New-Object System.Drawing.Point(38, 135)
    $lvwDCs.Size = New-Object System.Drawing.Size(450, 180)
    $lvwDCs.BackColor = $Script:Theme.InputBg
    $lvwDCs.ForeColor = $Script:Theme.TextPrimary
    $lvwDCs.Font = $Script:FontBody
    $lvwDCs.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    [void]$lvwDCs.Columns.Add("Name", 190)
    [void]$lvwDCs.Columns.Add("Site", 130)
    [void]$lvwDCs.Columns.Add("Status", 110)

    $sampleDCs = @(
        @{ Name = "DC01.corp.contoso.local"; Site = "Default-First-Site"; Status = "Online (PDC, GC)" },
        @{ Name = "DC02.corp.contoso.local"; Site = "Default-First-Site"; Status = "Online (GC, Writable)" },
        @{ Name = "DC03.branch.contoso.local"; Site = "London-Branch"; Status = "Online (Writable)" }
    )
    foreach ($dc in $sampleDCs) {
        $lvi = New-Object System.Windows.Forms.ListViewItem($dc.Name)
        [void]$lvi.SubItems.Add($dc.Site)
        [void]$lvi.SubItems.Add($dc.Status)
        $lvi.Tag = $dc.Name
        if ($dc.Name -eq $currentRoot.PDCEmulator) {
            $lvi.Selected = $true
        }
        [void]$lvwDCs.Items.Add($lvi)
    }
    $dlg.Controls.Add($lvwDCs)

    $rbAny.Add_CheckedChanged({
        $lvwDCs.Enabled = $rbThis.Checked
    })

    # Buttons
    $btnConnect = New-Object ADUCK.DarkButton
    $btnConnect.Text = "OK"
    $btnConnect.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $btnConnect.Location = New-Object System.Drawing.Point(255, 345)
    $btnConnect.Size = New-Object System.Drawing.Size(110, 36)
    $btnConnect.Font = $Script:FontSmallBold
    $btnConnect.NormalBackColor = $Script:Theme.AccentDark
    $btnConnect.NormalForeColor = [System.Drawing.Color]::White
    $btnConnect.NormalBorderColor = $Script:Theme.Accent
    $btnConnect.HoverBackColor = $Script:Theme.AccentHover
    $btnConnect.HoverBorderColor = $Script:Theme.Accent
    $dlg.Controls.Add($btnConnect)

    $btnCancel = New-Object ADUCK.DarkButton
    $btnCancel.Text = "Cancel"
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $btnCancel.Location = New-Object System.Drawing.Point(378, 345)
    $btnCancel.Size = New-Object System.Drawing.Size(110, 36)
    $btnCancel.Font = $Script:FontSmallBold
    $dlg.Controls.Add($btnCancel)

    $dlg.AcceptButton = $btnConnect
    $dlg.CancelButton = $btnCancel

    if ($dlg.ShowDialog($Script:MainForm) -eq [System.Windows.Forms.DialogResult]::OK) {
        $selectedDC = if ($rbAny.Checked) {
            "DC01.corp.contoso.local"
        } elseif ($lvwDCs.SelectedItems.Count -gt 0) {
            $lvwDCs.SelectedItems[0].Tag
        } else {
            $currentRoot.PDCEmulator
        }
        Set-ADActiveDomainController -DCName $selectedDC
    }
}

# -----------------------------------------------------------------------------
# Dialog: Raise Domain Functional Level
# -----------------------------------------------------------------------------
function Show-RaiseDomainFunctionalLevelDialog {
    $currentRoot = Get-ADRootInformation
    $currentLevelRaw = if ($currentRoot.DomainMode) { $currentRoot.DomainMode } else { "Windows2016Domain" }

    $friendlyCurrent = switch ($currentLevelRaw) {
        "Windows2008Domain"       { "Windows Server 2008" }
        "Windows2008R2Domain"     { "Windows Server 2008 R2" }
        "Windows2012Domain"       { "Windows Server 2012" }
        "Windows2012R2Domain"     { "Windows Server 2012 R2" }
        "Windows2016Domain"       { "Windows Server 2016" }
        "Windows2019Domain"       { "Windows Server 2019" }
        "Windows2022Domain"       { "Windows Server 2022" }
        "Windows2025Domain"       { "Windows Server 2025" }
        default                   { "$currentLevelRaw" }
    }

    $dlg = New-ModernDialog -Title "Raise Domain Functional Level" -Width 500 -Height 400

    # Header
    $pnlHdr = New-Object System.Windows.Forms.Panel
    $pnlHdr.Location = New-Object System.Drawing.Point(0, 0)
    $pnlHdr.Size = New-Object System.Drawing.Size(500, 60)
    $pnlHdr.BackColor = $Script:Theme.SurfaceAlt
    $dlg.Controls.Add($pnlHdr)

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "Raise Domain Functional Level"
    $lblTitle.Font = $Script:FontTitle
    $lblTitle.ForeColor = $Script:Theme.TextPrimary
    $lblTitle.Location = New-Object System.Drawing.Point(20, 12)
    $lblTitle.AutoSize = $true
    $pnlHdr.Controls.Add($lblTitle)

    $lblSub = New-Object System.Windows.Forms.Label
    $lblSub.Text = "Domain: $($currentRoot.Name)"
    $lblSub.Font = $Script:FontSmall
    $lblSub.ForeColor = $Script:Theme.TextSecondary
    $lblSub.Location = New-Object System.Drawing.Point(22, 34)
    $lblSub.AutoSize = $true
    $pnlHdr.Controls.Add($lblSub)

    # Current Level
    $lblCur = New-Object System.Windows.Forms.Label
    $lblCur.Text = "Current domain functional level:"
    $lblCur.Font = $Script:FontBodyBold
    $lblCur.ForeColor = $Script:Theme.TextPrimary
    $lblCur.Location = New-Object System.Drawing.Point(20, 80)
    $lblCur.AutoSize = $true
    $dlg.Controls.Add($lblCur)

    $lblCurVal = New-Object System.Windows.Forms.Label
    $lblCurVal.Text = $friendlyCurrent
    $lblCurVal.Font = $Script:FontBody
    $lblCurVal.ForeColor = $Script:Theme.Accent
    $lblCurVal.Location = New-Object System.Drawing.Point(22, 105)
    $lblCurVal.AutoSize = $true
    $dlg.Controls.Add($lblCurVal)

    # Target Level
    $lblTarget = New-Object System.Windows.Forms.Label
    $lblTarget.Text = "Select an available domain functional level:"
    $lblTarget.Font = $Script:FontBodyBold
    $lblTarget.ForeColor = $Script:Theme.TextPrimary
    $lblTarget.Location = New-Object System.Drawing.Point(20, 140)
    $lblTarget.AutoSize = $true
    $dlg.Controls.Add($lblTarget)

    $cboLevel = New-Object System.Windows.Forms.ComboBox
    $cboLevel.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $cboLevel.Location = New-Object System.Drawing.Point(20, 168)
    $cboLevel.Size = New-Object System.Drawing.Size(440, 28)
    $cboLevel.BackColor = $Script:Theme.InputBg
    $cboLevel.ForeColor = $Script:Theme.TextPrimary
    $cboLevel.Font = $Script:FontBody
    $cboLevel.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat

    $availableLevels = @(
        @{ Display = "Windows Server 2016"; Value = "Windows2016Domain" },
        @{ Display = "Windows Server 2019"; Value = "Windows2019Domain" },
        @{ Display = "Windows Server 2022"; Value = "Windows2022Domain" },
        @{ Display = "Windows Server 2025"; Value = "Windows2025Domain" }
    )
    foreach ($lvl in $availableLevels) {
        [void]$cboLevel.Items.Add($lvl.Display)
    }
    $cboLevel.SelectedIndex = [Math]::Min(1, $cboLevel.Items.Count - 1)
    $dlg.Controls.Add($cboLevel)

    # Warning Box
    $pnlWarn = New-Object System.Windows.Forms.Panel
    $pnlWarn.Location = New-Object System.Drawing.Point(20, 215)
    $pnlWarn.Size = New-Object System.Drawing.Size(440, 75)
    $pnlWarn.BackColor = $Script:Theme.WarningBg
    $pnlWarn.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $dlg.Controls.Add($pnlWarn)

    $lblWarn = New-Object System.Windows.Forms.Label
    $lblWarn.Text = "Warning: After you raise the domain functional level, it cannot be reversed. Verify that all domain controllers in the domain run an operating system that supports this functional level."
    $lblWarn.ForeColor = $Script:Theme.Warning
    $lblWarn.Font = $Script:FontSmall
    $lblWarn.Location = New-Object System.Drawing.Point(10, 8)
    $lblWarn.Size = New-Object System.Drawing.Size(420, 58)
    $pnlWarn.Controls.Add($lblWarn)

    # Buttons
    $btnRaise = New-Object ADUCK.DarkButton
    $btnRaise.Text = "Raise"
    $btnRaise.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $btnRaise.Location = New-Object System.Drawing.Point(235, 305)
    $btnRaise.Size = New-Object System.Drawing.Size(110, 36)
    $btnRaise.Font = $Script:FontSmallBold
    $btnRaise.NormalBackColor = $Script:Theme.AccentDark
    $btnRaise.NormalForeColor = [System.Drawing.Color]::White
    $btnRaise.NormalBorderColor = $Script:Theme.Accent
    $btnRaise.HoverBackColor = $Script:Theme.AccentHover
    $btnRaise.HoverBorderColor = $Script:Theme.Accent
    $dlg.Controls.Add($btnRaise)

    $btnCancel = New-Object ADUCK.DarkButton
    $btnCancel.Text = "Cancel"
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $btnCancel.Location = New-Object System.Drawing.Point(355, 305)
    $btnCancel.Size = New-Object System.Drawing.Size(105, 36)
    $btnCancel.Font = $Script:FontSmallBold
    $dlg.Controls.Add($btnCancel)

    $dlg.AcceptButton = $btnRaise
    $dlg.CancelButton = $btnCancel

    if ($dlg.ShowDialog($Script:MainForm) -eq [System.Windows.Forms.DialogResult]::OK) {
        $selectedText = $cboLevel.SelectedItem
        $selectedMatch = $availableLevels | Where-Object { $_.Display -eq $selectedText }
        $targetVal = if ($selectedMatch) { $selectedMatch.Value } else { "Windows2019Domain" }

        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Are you sure you want to raise the domain functional level to $selectedText? This change cannot be undone.",
            "Confirm Raise Domain Functional Level",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
            Set-ADDomainFunctionalLevel -NewLevel $targetVal
            [System.Windows.Forms.MessageBox]::Show(
                "The domain functional level was successfully raised to $selectedText.",
                "Success",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
            Set-StatusMessage "Domain functional level raised to: $selectedText"
        }
    }
}

# Dialog UI Control Factory Helpers
# -----------------------------------------------------------------------------
function New-ThemedLabel {
    param([string]$Text, [int]$X, [int]$Y, [int]$Width = 0, [bool]$Secondary = $false, [bool]$Bold = $false)
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Text
    $lbl.Location = New-Object System.Drawing.Point($X, $Y)
    if ($Width -gt 0) { $lbl.Size = New-Object System.Drawing.Size($Width, 20); $lbl.AutoSize = $false } else { $lbl.AutoSize = $true }
    if ($Secondary) { $lbl.ForeColor = $Script:Theme.TextSecondary } else { $lbl.ForeColor = $Script:Theme.TextPrimary }
    if ($Bold) { $lbl.Font = $Script:FontBodyBold } else { $lbl.Font = $Script:FontBody }
    return $lbl
}

function New-ThemedTextBox {
    param([string]$Text, [int]$X, [int]$Y, [int]$Width, [int]$Height = 24, [bool]$Multiline = $false, [bool]$ReadOnly = $false)
    $txt = New-Object System.Windows.Forms.TextBox
    if ($Text) { $txt.Text = $Text } else { $txt.Text = "" }
    $txt.Location = New-Object System.Drawing.Point($X, $Y)
    $txt.Size = New-Object System.Drawing.Size($Width, $Height)
    $txt.Multiline = $Multiline
    $txt.ReadOnly = $ReadOnly
    if ($Multiline) { $txt.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical }
    if ($ReadOnly) { $txt.BackColor = $Script:Theme.SurfaceAlt } else { $txt.BackColor = $Script:Theme.InputBg }
    if ($ReadOnly) { $txt.ForeColor = $Script:Theme.TextSecondary } else { $txt.ForeColor = $Script:Theme.TextPrimary }
    $txt.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $txt.Font = $Script:FontBody
    return $txt
}

function New-ThemedButton {
    param([string]$Text, [int]$X, [int]$Y, [int]$Width = 85, [int]$Height = 26, [bool]$Primary = $false)
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $Text
    $btn.Location = New-Object System.Drawing.Point($X, $Y)
    $btn.Size = New-Object System.Drawing.Size($Width, $Height)
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btn.Font = $Script:FontBody
    if ($Primary) {
        $btn.BackColor = $Script:Theme.AccentDark
        $btn.ForeColor = [System.Drawing.Color]::White
        $btn.FlatAppearance.BorderColor = $Script:Theme.Accent
    } else {
        $btn.BackColor = $Script:Theme.SurfaceAlt
        $btn.ForeColor = $Script:Theme.TextPrimary
        $btn.FlatAppearance.BorderColor = $Script:Theme.Border
    }
    return $btn
}

function New-ThemedCheckBox {
    param([string]$Text, [int]$X, [int]$Y, [bool]$Checked = $false, [bool]$Enabled = $true)
    $chk = New-Object System.Windows.Forms.CheckBox
    $chk.Text = $Text
    $chk.Location = New-Object System.Drawing.Point($X, $Y)
    $chk.AutoSize = $true
    $chk.Checked = $Checked
    $chk.Enabled = $Enabled
    $chk.ForeColor = $Script:Theme.TextPrimary
    $chk.Font = $Script:FontBody
    return $chk
}

function New-ThemedRadioButton {
    param([string]$Text, [int]$X, [int]$Y, [bool]$Checked = $false)
    $rb = New-Object System.Windows.Forms.RadioButton
    $rb.Text = $Text
    $rb.Location = New-Object System.Drawing.Point($X, $Y)
    $rb.AutoSize = $true
    $rb.Checked = $Checked
    $rb.ForeColor = $Script:Theme.TextPrimary
    $rb.Font = $Script:FontBody
    return $rb
}

function New-ThemedGroupBox {
    param([string]$Title, [int]$X, [int]$Y, [int]$Width, [int]$Height)
    $gb = New-Object System.Windows.Forms.GroupBox
    $gb.Text = $Title
    $gb.Location = New-Object System.Drawing.Point($X, $Y)
    $gb.Size = New-Object System.Drawing.Size($Width, $Height)
    $gb.ForeColor = $Script:Theme.TextPrimary
    $gb.Font = $Script:FontBody
    return $gb
}

function New-ThemedComboBox {
    param([string[]]$Items, [int]$X, [int]$Y, [int]$Width, [string]$Selected = "")
    $cb = New-Object System.Windows.Forms.ComboBox
    $cb.Location = New-Object System.Drawing.Point($X, $Y)
    $cb.Size = New-Object System.Drawing.Size($Width, 24)
    $cb.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $cb.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $cb.BackColor = $Script:Theme.InputBg
    $cb.ForeColor = $Script:Theme.TextPrimary
    $cb.Font = $Script:FontBody
    if ($Items) {
        foreach ($it in $Items) { $cb.Items.Add($it) | Out-Null }
        if ($Selected -and $cb.Items.Contains($Selected)) {
            $cb.SelectedItem = $Selected
        } elseif ($cb.Items.Count -gt 0) {
            $cb.SelectedIndex = 0
        }
    }
    return $cb
}

# -----------------------------------------------------------------------------
# Dialog: Attribute Editor Dialog (Sub-Modal for Editing Values)
# -----------------------------------------------------------------------------
function Show-AttributeEditorDialog {
    param(
        [string]$AttributeName,
        [string]$Syntax,
        $CurrentValue
    )

    $dlgAttr = New-Object System.Windows.Forms.Form
    $dlgAttr.Text = "$AttributeName Properties"
    $dlgAttr.Size = New-Object System.Drawing.Size(460, 360)
    $dlgAttr.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $dlgAttr.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dlgAttr.MaximizeBox = $false
    $dlgAttr.MinimizeBox = $false
    $dlgAttr.BackColor = $Script:Theme.Surface
    $dlgAttr.ForeColor = $Script:Theme.TextPrimary
    $dlgAttr.Font = $Script:FontBody
    if ($Script:DuckIcon) { $dlgAttr.Icon = $Script:DuckIcon }
    [ADUCK.NativeMethods]::ApplyDarkTitleBar($dlgAttr.Handle, ($Script:Theme.Name -eq 'Dark'))

    $lblAttrName = New-ThemedLabel -Text "Attribute: $AttributeName" -X 16 -Y 16 -Bold $true
    $lblSyntax = New-ThemedLabel -Text "Syntax: $Syntax" -X 16 -Y 38 -Secondary $true
    $dlgAttr.Controls.AddRange(@($lblAttrName, $lblSyntax))

    $isMulti = ($Syntax -like "*Multi*" -or $CurrentValue -is [System.Array] -or $CurrentValue -is [System.Collections.IList])
    $resultValue = $CurrentValue
    $hasChanged = $false

    if ($isMulti) {
        $lblValDesc = New-ThemedLabel -Text "Values:" -X 16 -Y 68
        $lstMulti = New-Object System.Windows.Forms.ListBox
        $lstMulti.Location = New-Object System.Drawing.Point(16, 90)
        $lstMulti.Size = New-Object System.Drawing.Size(300, 150)
        $lstMulti.BackColor = $Script:Theme.InputBg
        $lstMulti.ForeColor = $Script:Theme.TextPrimary
        $lstMulti.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
        $lstMulti.Font = $Script:FontBody

        $multiItems = [System.Collections.ArrayList]@()
        if ($CurrentValue -is [System.Array] -or $CurrentValue -is [System.Collections.IList]) {
            foreach ($item in $CurrentValue) { if ($item) { $null = $multiItems.Add([string]$item); $null = $lstMulti.Items.Add([string]$item) } }
        } elseif ($CurrentValue -and $CurrentValue -ne "<not set>") {
            $parts = "$CurrentValue" -split ";\s*"
            foreach ($p in $parts) { if ($p) { $null = $multiItems.Add($p); $null = $lstMulti.Items.Add($p) } }
        }

        $txtNewVal = New-ThemedTextBox -Text "" -X 16 -Y 248 -Width 300
        $btnAddVal = New-ThemedButton -Text "Add" -X 330 -Y 247 -Width 85 -Primary $false
        $btnRemVal = New-ThemedButton -Text "Remove" -X 330 -Y 90 -Width 85 -Primary $false
        $btnClearVal = New-ThemedButton -Text "Clear" -X 330 -Y 125 -Width 85 -Primary $false

        $btnAddVal.Add_Click({
            if ($txtNewVal.Text.Trim()) {
                $null = $multiItems.Add($txtNewVal.Text.Trim())
                $null = $lstMulti.Items.Add($txtNewVal.Text.Trim())
                $txtNewVal.Text = ""
            }
        })
        $btnRemVal.Add_Click({
            if ($lstMulti.SelectedIndex -ge 0) {
                $idx = $lstMulti.SelectedIndex
                $multiItems.RemoveAt($idx)
                $lstMulti.Items.RemoveAt($idx)
            }
        })
        $btnClearVal.Add_Click({
            $multiItems.Clear()
            $lstMulti.Items.Clear()
        })

        $dlgAttr.Controls.AddRange(@($lblValDesc, $lstMulti, $txtNewVal, $btnAddVal, $btnRemVal, $btnClearVal))
    } elseif ($Syntax -eq "Boolean") {
        $lblValDesc = New-ThemedLabel -Text "Value:" -X 16 -Y 68
        $rbTrue = New-ThemedRadioButton -Text "TRUE" -X 20 -Y 95 -Checked ($CurrentValue -eq $true -or "$CurrentValue" -eq "TRUE")
        $rbFalse = New-ThemedRadioButton -Text "FALSE" -X 20 -Y 125 -Checked ($CurrentValue -eq $false -or "$CurrentValue" -eq "FALSE")
        $rbNotSet = New-ThemedRadioButton -Text "<not set>" -X 20 -Y 155 -Checked ($CurrentValue -eq "<not set>" -or $null -eq $CurrentValue)
        $dlgAttr.Controls.AddRange(@($lblValDesc, $rbTrue, $rbFalse, $rbNotSet))
    } else {
        $lblValDesc = New-ThemedLabel -Text "Value:" -X 16 -Y 68
        $initVal = $(if ($CurrentValue -eq "<not set>") { "" } else { "$CurrentValue" })
        $txtSingle = New-ThemedTextBox -Text $initVal -X 16 -Y 90 -Width 395 -Height 120 -Multiline $true
        $btnClearSingle = New-ThemedButton -Text "Clear Attribute" -X 16 -Y 220 -Width 120
        $btnClearSingle.Add_Click({ $txtSingle.Text = "" })
        $dlgAttr.Controls.AddRange(@($lblValDesc, $txtSingle, $btnClearSingle))
    }

    $btnAttrOK = New-ThemedButton -Text "OK" -X 225 -Y 280 -Width 85 -Primary $true
    $btnAttrCancel = New-ThemedButton -Text "Cancel" -X 325 -Y 280 -Width 85 -Primary $false
    $btnAttrOK.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $btnAttrCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlgAttr.AcceptButton = $btnAttrOK
    $dlgAttr.CancelButton = $btnAttrCancel
    $dlgAttr.Controls.AddRange(@($btnAttrOK, $btnAttrCancel))

    $res = $dlgAttr.ShowDialog()
    if ($res -eq [System.Windows.Forms.DialogResult]::OK) {
        $hasChanged = $true
        if ($isMulti) {
            $resultValue = @($multiItems)
        } elseif ($Syntax -eq "Boolean") {
            if ($rbTrue.Checked) { $resultValue = $true }
            elseif ($rbFalse.Checked) { $resultValue = $false }
            else { $resultValue = "<not set>" }
        } else {
            $resultValue = $(if ([string]::IsNullOrWhiteSpace($txtSingle.Text)) { "<not set>" } else { $txtSingle.Text.Trim() })
        }
    }
    $dlgAttr.Dispose()
    return @{ Changed = $hasChanged; Value = $resultValue }
}

# -----------------------------------------------------------------------------
# Function: Update-AttributeListView
# -----------------------------------------------------------------------------
function Update-AttributeListView {
    param(
        $ListView,
        [string]$FilterText = "",
        [bool]$OnlyValues = $false,
        [array]$LdapDefs = @(),
        $TargetObject
    )

    if (-not $ListView -or -not $TargetObject) { return }

    $ListView.BeginUpdate()
    $ListView.Items.Clear()
    foreach ($def in $LdapDefs) {
        $propVal = $TargetObject.$($def.Field)
        $displayVal = "<not set>"
        if ($null -ne $propVal -and $propVal -ne "") {
            if ($propVal -is [System.Array] -or $propVal -is [System.Collections.IList]) {
                $displayVal = $(if ($propVal.Count -gt 0) { $propVal -join "; " } else { "<not set>" })
            } else {
                $displayVal = "$propVal"
            }
        }

        if ($OnlyValues -and $displayVal -eq "<not set>") {
            continue
        }

        if ($FilterText -and ($def.Name -notlike "*$FilterText*")) {
            continue
        }

        $lvi = New-Object System.Windows.Forms.ListViewItem($def.Name)
        $null = $lvi.SubItems.Add($def.Syntax)
        $null = $lvi.SubItems.Add($displayVal)
        $lvi.Tag = @{ Def = $def; Value = $propVal; Display = $displayVal }
        if ($displayVal -eq "<not set>") { $lvi.ForeColor = $Script:Theme.TextSecondary }
        $null = $ListView.Items.Add($lvi)
    }
    $ListView.EndUpdate()
}

# -----------------------------------------------------------------------------
# Dialog: Object Properties (Full Tabbed Editor)
# -----------------------------------------------------------------------------
function Show-PropertiesDialog {
    param($DirectoryObject, [switch]$HeadlessTest)

    $isUser = ($DirectoryObject.ObjectClass -eq 'user')
    $isGroup = ($DirectoryObject.ObjectClass -eq 'group')
    $isComputer = ($DirectoryObject.ObjectClass -eq 'computer')

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "$($DirectoryObject.Name) Properties"
    $dlg.Size = New-Object System.Drawing.Size(620, 720)
    $dlg.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.BackColor = $Script:Theme.Surface
    $dlg.ForeColor = $Script:Theme.TextPrimary
    $dlg.Font = $Script:FontBody
    if ($Script:DuckIcon) { $dlg.Icon = $Script:DuckIcon }
    [ADUCK.NativeMethods]::ApplyDarkTitleBar($dlg.Handle, ($Script:Theme.Name -eq 'Dark'))

    $tabs = New-Object System.Windows.Forms.TabControl
    $tabs.Multiline = $true
    $tabs.Location = New-Object System.Drawing.Point(12, 10)
    $tabs.Size = New-Object System.Drawing.Size(580, 620)
    $tabs.Font = $Script:FontBody

    # Define Tabs List matching MMC layout
    $tabNames = $(if ($isUser) {
        @(
            'Published Certificates', 'Member Of', 'Password Replication', 'Dial-in', 'Object',
            'Security', 'Environment', 'Sessions', 'Remote control',
            'Remote Desktop Services Profile', 'COM+', 'Attribute Editor',
            'General', 'Address', 'Account', 'Profile', 'Telephones', 'Organization'
        )
    } elseif ($isGroup) {
        @('General', 'Members', 'Member Of', 'Managed By', 'Object', 'Security', 'Attribute Editor')
    } elseif ($isComputer) {
        @('Delegation', 'Password Replication', 'Location', 'Managed By', 'Dial-in', 'Object', 'Security', 'Attribute Editor', 'General', 'Operating System', 'Member Of')
    } else {
        @('General', 'Object', 'Security', 'Attribute Editor')
    })

    foreach ($tName in $tabNames) {
        $tp = New-Object System.Windows.Forms.TabPage
        $tp.Text = $tName
        $tp.Name = $tName
        $tp.BackColor = $Script:Theme.Surface
        $tp.ForeColor = $Script:Theme.TextPrimary
        $tp.AutoScroll = $true
        $tabs.TabPages.Add($tp) | Out-Null
    }

    # =========================================================================
    # TAB: GENERAL
    # =========================================================================
    $tpGen = $tabs.TabPages['General']
    $lblNameHdr = New-ThemedLabel -Text $DirectoryObject.Name -X 56 -Y 16 -Bold $true
    $divGen1 = New-Object System.Windows.Forms.Panel; $divGen1.Location = New-Object System.Drawing.Point(16, 48); $divGen1.Size = New-Object System.Drawing.Size(540, 1); $divGen1.BackColor = $Script:Theme.Border

    if ($isUser) {
        $lblFirst = New-ThemedLabel -Text "First name:" -X 16 -Y 64
        $txtFirst = New-ThemedTextBox -Text $DirectoryObject.givenName -X 110 -Y 61 -Width 250
        $lblInit = New-ThemedLabel -Text "Initials:" -X 380 -Y 64
        $txtInit = New-ThemedTextBox -Text $DirectoryObject.initials -X 435 -Y 61 -Width 120

        $lblLast = New-ThemedLabel -Text "Last name:" -X 16 -Y 98
        $txtLast = New-ThemedTextBox -Text $DirectoryObject.sn -X 110 -Y 95 -Width 445

        $dispVal = $(if ($DirectoryObject.displayName) { $DirectoryObject.displayName } else { $DirectoryObject.Name })
        $lblDisp = New-ThemedLabel -Text "Display name:" -X 16 -Y 132
        $txtDisp = New-ThemedTextBox -Text $dispVal -X 110 -Y 129 -Width 445

        $lblDesc = New-ThemedLabel -Text "Description:" -X 16 -Y 166
        $txtDesc = New-ThemedTextBox -Text $DirectoryObject.Description -X 110 -Y 163 -Width 445

        $lblOffice = New-ThemedLabel -Text "Office:" -X 16 -Y 200
        $txtOffice = New-ThemedTextBox -Text $DirectoryObject.office -X 110 -Y 197 -Width 445

        $divGen2 = New-Object System.Windows.Forms.Panel; $divGen2.Location = New-Object System.Drawing.Point(16, 235); $divGen2.Size = New-Object System.Drawing.Size(540, 1); $divGen2.BackColor = $Script:Theme.Border

        $lblPhone = New-ThemedLabel -Text "Telephone number:" -X 16 -Y 252
        $txtPhone = New-ThemedTextBox -Text $DirectoryObject.telephoneNumber -X 130 -Y 249 -Width 335
        $btnOtherPhone = New-ThemedButton -Text "Other..." -X 475 -Y 248 -Width 80

        $lblMail = New-ThemedLabel -Text "E-mail:" -X 16 -Y 286
        $txtMail = New-ThemedTextBox -Text $DirectoryObject.mail -X 130 -Y 283 -Width 425

        $lblWeb = New-ThemedLabel -Text "Web page:" -X 16 -Y 320
        $txtWeb = New-ThemedTextBox -Text $DirectoryObject.wWWHomePage -X 130 -Y 317 -Width 335
        $btnOtherWeb = New-ThemedButton -Text "Other..." -X 475 -Y 316 -Width 80

        $tpGen.Controls.AddRange(@(
            $lblNameHdr, $divGen1,
            $lblFirst, $txtFirst, $lblInit, $txtInit,
            $lblLast, $txtLast, $lblDisp, $txtDisp,
            $lblDesc, $txtDesc, $lblOffice, $txtOffice,
            $divGen2,
            $lblPhone, $txtPhone, $btnOtherPhone,
            $lblMail, $txtMail,
            $lblWeb, $txtWeb, $btnOtherWeb
        ))
    } elseif ($isGroup) {
        $lblGrpPre = New-ThemedLabel -Text "Group name (pre-Windows 2000):" -X 16 -Y 60
        $txtGrpPre = New-ThemedTextBox -Text $DirectoryObject.sAMAccountName -X 235 -Y 57 -Width 320 -ReadOnly $true

        $lblGrpDesc = New-ThemedLabel -Text "Description:" -X 16 -Y 95
        $txtGrpDesc = New-ThemedTextBox -Text $DirectoryObject.Description -X 110 -Y 92 -Width 445

        $lblGrpMail = New-ThemedLabel -Text "E-mail:" -X 16 -Y 130
        $txtGrpMail = New-ThemedTextBox -Text $DirectoryObject.mail -X 110 -Y 127 -Width 445

        $gbScope = New-ThemedGroupBox -Title "Group scope" -X 16 -Y 165 -Width 260 -Height 110
        $rbDomainLocal = New-ThemedRadioButton -Text "Domain local" -X 16 -Y 24 -Checked ($DirectoryObject.GroupScope -eq 'DomainLocal')
        $rbGlobal = New-ThemedRadioButton -Text "Global" -X 16 -Y 50 -Checked ($DirectoryObject.GroupScope -eq 'Global')
        $rbUniversal = New-ThemedRadioButton -Text "Universal" -X 16 -Y 76 -Checked ($DirectoryObject.GroupScope -eq 'Universal')
        $gbScope.Controls.AddRange(@($rbDomainLocal, $rbGlobal, $rbUniversal))

        $gbType = New-ThemedGroupBox -Title "Group type" -X 300 -Y 165 -Width 255 -Height 110
        $rbSecurity = New-ThemedRadioButton -Text "Security" -X 16 -Y 30 -Checked ($DirectoryObject.GroupType -eq 'Security')
        $rbDistribution = New-ThemedRadioButton -Text "Distribution" -X 16 -Y 60 -Checked ($DirectoryObject.GroupType -eq 'Distribution')
        $gbType.Controls.AddRange(@($rbSecurity, $rbDistribution))

        $lblGrpNotes = New-ThemedLabel -Text "Notes:" -X 16 -Y 285
        $txtGrpNotes = New-ThemedTextBox -Text $DirectoryObject.info -X 16 -Y 310 -Width 540 -Height 120 -Multiline $true

        $tpGen.Controls.AddRange(@($lblNameHdr, $divGen1, $lblGrpPre, $txtGrpPre, $lblGrpDesc, $txtGrpDesc, $lblGrpMail, $txtGrpMail, $gbScope, $gbType, $lblGrpNotes, $txtGrpNotes))
    } elseif ($isComputer) {
        $lblCompName = New-ThemedLabel -Text "Computer name:" -X 16 -Y 60
        $txtCompName = New-ThemedTextBox -Text $DirectoryObject.Name -X 160 -Y 57 -Width 395 -ReadOnly $true

        $lblCompPre = New-ThemedLabel -Text "Computer name (pre-Windows 2000):" -X 16 -Y 95
        $txtCompPre = New-ThemedTextBox -Text $DirectoryObject.sAMAccountName -X 245 -Y 92 -Width 310 -ReadOnly $true

        $lblCompDns = New-ThemedLabel -Text "DNS name:" -X 16 -Y 130
        $txtCompDns = New-ThemedTextBox -Text $DirectoryObject.DNSHostName -X 160 -Y 127 -Width 395

        $lblCompDesc = New-ThemedLabel -Text "Description:" -X 16 -Y 165
        $txtCompDesc = New-ThemedTextBox -Text $DirectoryObject.Description -X 160 -Y 162 -Width 395

        $lblCompRole = New-ThemedLabel -Text "Role:" -X 16 -Y 200
        $txtCompRole = New-ThemedTextBox -Text "Domain Controller / Workstation" -X 160 -Y 197 -Width 395 -ReadOnly $true

        $tpGen.Controls.AddRange(@($lblNameHdr, $divGen1, $lblCompName, $txtCompName, $lblCompPre, $txtCompPre, $lblCompDns, $txtCompDns, $lblCompDesc, $txtCompDesc, $lblCompRole, $txtCompRole))
    } else {
        $lblObjName = New-ThemedLabel -Text "Name:" -X 16 -Y 60
        $txtObjName = New-ThemedTextBox -Text $DirectoryObject.Name -X 110 -Y 57 -Width 445 -ReadOnly $true
        $lblObjDesc = New-ThemedLabel -Text "Description:" -X 16 -Y 95
        $txtObjDesc = New-ThemedTextBox -Text $DirectoryObject.Description -X 110 -Y 92 -Width 445
        $tpGen.Controls.AddRange(@($lblNameHdr, $divGen1, $lblObjName, $txtObjName, $lblObjDesc, $txtObjDesc))
    }

    # =========================================================================
    # TAB: ADDRESS
    # =========================================================================
    if ($tabs.TabPages.ContainsKey('Address')) {
        $tpAddr = $tabs.TabPages['Address']
        $lblStreet = New-ThemedLabel -Text "Street:" -X 16 -Y 20
        $txtStreet = New-ThemedTextBox -Text $DirectoryObject.streetAddress -X 130 -Y 17 -Width 420 -Height 55 -Multiline $true

        $lblPOBox = New-ThemedLabel -Text "P.O. Box:" -X 16 -Y 85
        $txtPOBox = New-ThemedTextBox -Text $DirectoryObject.postOfficeBox -X 130 -Y 82 -Width 420

        $lblCity = New-ThemedLabel -Text "City:" -X 16 -Y 120
        $txtCity = New-ThemedTextBox -Text $DirectoryObject.l -X 130 -Y 117 -Width 420

        $lblState = New-ThemedLabel -Text "State/province:" -X 16 -Y 155
        $txtState = New-ThemedTextBox -Text $DirectoryObject.st -X 130 -Y 152 -Width 420

        $lblZip = New-ThemedLabel -Text "Zip/Postal Code:" -X 16 -Y 190
        $txtZip = New-ThemedTextBox -Text $DirectoryObject.postalCode -X 130 -Y 187 -Width 420

        $countryVal = $(if ($DirectoryObject.co) { $DirectoryObject.co } else { "United States" })
        $lblCountry = New-ThemedLabel -Text "Country/region:" -X 16 -Y 225
        $txtCountry = New-ThemedTextBox -Text $countryVal -X 130 -Y 222 -Width 420

        $tpAddr.Controls.AddRange(@(
            $lblStreet, $txtStreet, $lblPOBox, $txtPOBox,
            $lblCity, $txtCity, $lblState, $txtState,
            $lblZip, $txtZip, $lblCountry, $txtCountry
        ))
    }

    # =========================================================================
    # TAB: ACCOUNT
    # =========================================================================
    if ($tabs.TabPages.ContainsKey('Account')) {
        $tpAcc = $tabs.TabPages['Account']

        $lblUpn = New-ThemedLabel -Text "User logon name:" -X 16 -Y 16
        $upnParts = $(if ($DirectoryObject.userPrincipalName) { $DirectoryObject.userPrincipalName -split "@" } else { @($DirectoryObject.sAMAccountName, "corp.contoso.local") })
        $txtUpnPrefix = New-ThemedTextBox -Text $upnParts[0] -X 16 -Y 36 -Width 220
        $lblAt = New-ThemedLabel -Text "@" -X 242 -Y 38
        $upnSuffixVal = $(if ($upnParts.Count -gt 1) { $upnParts[1] } else { "corp.contoso.local" })
        $cbUpnSuffix = New-ThemedComboBox -Items @("corp.contoso.local", "contoso.com") -X 260 -Y 36 -Width 290 -Selected $upnSuffixVal

        $lblPre2k = New-ThemedLabel -Text "User logon name (pre-Windows 2000):" -X 16 -Y 72
        $lblPreDom = New-ThemedLabel -Text "CORP\" -X 16 -Y 95
        $txtSam = New-ThemedTextBox -Text $DirectoryObject.sAMAccountName -X 70 -Y 92 -Width 260

        $btnLogonHours = New-ThemedButton -Text "Logon Hours..." -X 345 -Y 91 -Width 100
        $btnLogonTo = New-ThemedButton -Text "Log On To..." -X 455 -Y 91 -Width 95

        $chkUnlock = New-ThemedCheckBox -Text "Unlock account (Account is currently locked out)" -X 16 -Y 130 -Checked $false -Enabled ([bool]$DirectoryObject.LockedOut)
        if ($DirectoryObject.LockedOut) { $chkUnlock.ForeColor = $Script:Theme.Warning }

        # Account Options Group
        $gbAccOpts = New-ThemedGroupBox -Title "Account options" -X 16 -Y 160 -Width 535 -Height 180
        $pnlOpts = New-Object System.Windows.Forms.Panel
        $pnlOpts.Location = New-Object System.Drawing.Point(10, 20)
        $pnlOpts.Size = New-Object System.Drawing.Size(515, 150)
        $pnlOpts.AutoScroll = $true

        $chkMustChange = New-ThemedCheckBox -Text "User must change password at next logon" -X 8 -Y 5 -Checked ([bool]$DirectoryObject.MustChangePasswordAtNextLogon)
        $chkCantChange = New-ThemedCheckBox -Text "User cannot change password" -X 8 -Y 30 -Checked ([bool]$DirectoryObject.CannotChangePassword)
        $chkPassNever = New-ThemedCheckBox -Text "Password never expires" -X 8 -Y 55 -Checked ([bool]$DirectoryObject.PasswordNeverExpires)
        $chkReversible = New-ThemedCheckBox -Text "Store password using reversible encryption" -X 8 -Y 80 -Checked $false
        $chkDisabled = New-ThemedCheckBox -Text "Account is disabled" -X 8 -Y 105 -Checked (-not [bool]$DirectoryObject.Enabled)
        $chkSmartcard = New-ThemedCheckBox -Text "Smart card is required for interactive logon" -X 8 -Y 130 -Checked $false
        $chkSensitive = New-ThemedCheckBox -Text "Account is sensitive and cannot be delegated" -X 8 -Y 155 -Checked $false
        $chkDES = New-ThemedCheckBox -Text "Use Kerberos DES encryption types for this account" -X 8 -Y 180 -Checked $false
        $chkNoPreauth = New-ThemedCheckBox -Text "Do not require Kerberos preauthentication" -X 8 -Y 205 -Checked $false

        $pnlOpts.Controls.AddRange(@($chkMustChange, $chkCantChange, $chkPassNever, $chkReversible, $chkDisabled, $chkSmartcard, $chkSensitive, $chkDES, $chkNoPreauth))
        $gbAccOpts.Controls.Add($pnlOpts)

        # Account Expires Group
        $gbExpires = New-ThemedGroupBox -Title "Account expires" -X 16 -Y 348 -Width 535 -Height 65
        $rbNeverExpires = New-ThemedRadioButton -Text "Never" -X 20 -Y 25 -Checked ($null -eq $DirectoryObject.AccountExpires -or $DirectoryObject.AccountExpires -eq "<not set>")
        $rbEndExpires = New-ThemedRadioButton -Text "End of:" -X 150 -Y 25 -Checked (-not $rbNeverExpires.Checked)
        $dtpExpires = New-Object System.Windows.Forms.DateTimePicker
        $dtpExpires.Location = New-Object System.Drawing.Point(230, 23)
        $dtpExpires.Size = New-Object System.Drawing.Size(130, 24)
        $dtpExpires.Format = [System.Windows.Forms.DateTimePickerFormat]::Short
        $dtpExpires.Enabled = $rbEndExpires.Checked
        $rbEndExpires.Add_CheckedChanged({ $dtpExpires.Enabled = $rbEndExpires.Checked })
        $gbExpires.Controls.AddRange(@($rbNeverExpires, $rbEndExpires, $dtpExpires))

        $tpAcc.Controls.AddRange(@(
            $lblUpn, $txtUpnPrefix, $lblAt, $cbUpnSuffix,
            $lblPre2k, $lblPreDom, $txtSam, $btnLogonHours, $btnLogonTo,
            $chkUnlock, $gbAccOpts, $gbExpires
        ))
    }

    # =========================================================================
    # TAB: PROFILE
    # =========================================================================
    if ($tabs.TabPages.ContainsKey('Profile')) {
        $tpProf = $tabs.TabPages['Profile']

        $gbUserProf = New-ThemedGroupBox -Title "User profile" -X 16 -Y 16 -Width 535 -Height 100
        $lblProfPath = New-ThemedLabel -Text "Profile path:" -X 16 -Y 28
        $txtProfPath = New-ThemedTextBox -Text $DirectoryObject.profilePath -X 120 -Y 25 -Width 390
        $lblScriptPath = New-ThemedLabel -Text "Logon script:" -X 16 -Y 62
        $txtScriptPath = New-ThemedTextBox -Text $DirectoryObject.scriptPath -X 120 -Y 59 -Width 390
        $gbUserProf.Controls.AddRange(@($lblProfPath, $txtProfPath, $lblScriptPath, $txtScriptPath))

        $gbHomeFolder = New-ThemedGroupBox -Title "Home folder" -X 16 -Y 126 -Width 535 -Height 120
        $rbLocalHome = New-ThemedRadioButton -Text "Local path:" -X 16 -Y 26 -Checked ($null -eq $DirectoryObject.homeDrive -or $DirectoryObject.homeDrive -eq "")
        $localHomeVal = $(if ($rbLocalHome.Checked) { $DirectoryObject.homeDirectory } else { "" })
        $txtLocalHome = New-ThemedTextBox -Text $localHomeVal -X 120 -Y 23 -Width 390
        $rbNetHome = New-ThemedRadioButton -Text "Connect:" -X 16 -Y 66 -Checked (-not $rbLocalHome.Checked)
        $homeDriveVal = $(if ($DirectoryObject.homeDrive) { $DirectoryObject.homeDrive } else { "H:" })
        $cbDriveLetter = New-ThemedComboBox -Items @("D:", "E:", "F:", "G:", "H:", "I:", "M:", "P:", "S:", "U:", "Z:") -X 120 -Y 64 -Width 60 -Selected $homeDriveVal
        $lblToNet = New-ThemedLabel -Text "To:" -X 190 -Y 66
        $netHomeVal = $(if ($rbNetHome.Checked) { $DirectoryObject.homeDirectory } else { "\\dc01\home\$($DirectoryObject.sAMAccountName)" })
        $txtNetHome = New-ThemedTextBox -Text $netHomeVal -X 220 -Y 63 -Width 290
        $gbHomeFolder.Controls.AddRange(@($rbLocalHome, $txtLocalHome, $rbNetHome, $cbDriveLetter, $lblToNet, $txtNetHome))

        $tpProf.Controls.AddRange(@($gbUserProf, $gbHomeFolder))
    }

    # =========================================================================
    # TAB: TELEPHONES
    # =========================================================================
    if ($tabs.TabPages.ContainsKey('Telephones')) {
        $tpTel = $tabs.TabPages['Telephones']

        $lblTelHome = New-ThemedLabel -Text "Home:" -X 16 -Y 20
        $txtTelHome = New-ThemedTextBox -Text $DirectoryObject.homePhone -X 110 -Y 17 -Width 355
        $btnTelHome = New-ThemedButton -Text "Other..." -X 475 -Y 16 -Width 80

        $lblTelPager = New-ThemedLabel -Text "Pager:" -X 16 -Y 55
        $txtTelPager = New-ThemedTextBox -Text $DirectoryObject.pager -X 110 -Y 52 -Width 355
        $btnTelPager = New-ThemedButton -Text "Other..." -X 475 -Y 51 -Width 80

        $lblTelMobile = New-ThemedLabel -Text "Mobile:" -X 16 -Y 90
        $txtTelMobile = New-ThemedTextBox -Text $DirectoryObject.mobile -X 110 -Y 87 -Width 355
        $btnTelMobile = New-ThemedButton -Text "Other..." -X 475 -Y 86 -Width 80

        $lblTelFax = New-ThemedLabel -Text "Fax:" -X 16 -Y 125
        $txtTelFax = New-ThemedTextBox -Text $DirectoryObject.facsimileTelephoneNumber -X 110 -Y 122 -Width 355
        $btnTelFax = New-ThemedButton -Text "Other..." -X 475 -Y 121 -Width 80

        $lblTelIP = New-ThemedLabel -Text "IP phone:" -X 16 -Y 160
        $txtTelIP = New-ThemedTextBox -Text $DirectoryObject.ipPhone -X 110 -Y 157 -Width 355
        $btnTelIP = New-ThemedButton -Text "Other..." -X 475 -Y 156 -Width 80

        $lblNotes = New-ThemedLabel -Text "Notes:" -X 16 -Y 195
        $txtNotes = New-ThemedTextBox -Text $DirectoryObject.info -X 16 -Y 218 -Width 540 -Height 140 -Multiline $true

        $tpTel.Controls.AddRange(@(
            $lblTelHome, $txtTelHome, $btnTelHome,
            $lblTelPager, $txtTelPager, $btnTelPager,
            $lblTelMobile, $txtTelMobile, $btnTelMobile,
            $lblTelFax, $txtTelFax, $btnTelFax,
            $lblTelIP, $txtTelIP, $btnTelIP,
            $lblNotes, $txtNotes
        ))
    }

    # =========================================================================
    # TAB: ORGANIZATION
    # =========================================================================
    if ($tabs.TabPages.ContainsKey('Organization')) {
        $tpOrg = $tabs.TabPages['Organization']

        $lblOrgTitle = New-ThemedLabel -Text "Title:" -X 16 -Y 18
        $txtOrgTitle = New-ThemedTextBox -Text $DirectoryObject.title -X 110 -Y 15 -Width 445

        $lblOrgDept = New-ThemedLabel -Text "Department:" -X 16 -Y 52
        $txtOrgDept = New-ThemedTextBox -Text $DirectoryObject.department -X 110 -Y 49 -Width 445

        $lblOrgComp = New-ThemedLabel -Text "Company:" -X 16 -Y 86
        $txtOrgComp = New-ThemedTextBox -Text $DirectoryObject.company -X 110 -Y 83 -Width 445

        $gbMgr = New-ThemedGroupBox -Title "Manager" -X 16 -Y 120 -Width 540 -Height 90
        $lblMgrName = New-ThemedLabel -Text "Name:" -X 16 -Y 28
        $txtMgrName = New-ThemedTextBox -Text $DirectoryObject.manager -X 70 -Y 25 -Width 450 -ReadOnly $true
        $btnMgrChange = New-ThemedButton -Text "Change..." -X 350 -Y 55 -Width 80
        $btnMgrClear = New-ThemedButton -Text "Clear" -X 440 -Y 55 -Width 80
        $btnMgrClear.Add_Click({ $txtMgrName.Text = "" })
        $gbMgr.Controls.AddRange(@($lblMgrName, $txtMgrName, $btnMgrChange, $btnMgrClear))

        $lblReports = New-ThemedLabel -Text "Direct reports:" -X 16 -Y 220
        $lstReports = New-Object System.Windows.Forms.ListBox
        $lstReports.Location = New-Object System.Drawing.Point(16, 242)
        $lstReports.Size = New-Object System.Drawing.Size(540, 75)
        $lstReports.BackColor = $Script:Theme.InputBg
        $lstReports.ForeColor = $Script:Theme.TextPrimary
        $lstReports.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
        $lstReports.Font = $Script:FontBody
        if ($DirectoryObject.directReports) {
            foreach ($rep in $DirectoryObject.directReports) { $null = $lstReports.Items.Add($rep) }
        }

        $lblEmpID = New-ThemedLabel -Text "Employee ID:" -X 16 -Y 330
        $txtEmpID = New-ThemedTextBox -Text $DirectoryObject.employeeID -X 110 -Y 327 -Width 160

        $lblEmpNum = New-ThemedLabel -Text "Employee #:" -X 290 -Y 330
        $txtEmpNum = New-ThemedTextBox -Text $DirectoryObject.employeeNumber -X 380 -Y 327 -Width 175

        $lblEmpType = New-ThemedLabel -Text "Employee Type:" -X 16 -Y 365
        $txtEmpType = New-ThemedTextBox -Text $DirectoryObject.employeeType -X 110 -Y 362 -Width 160

        $lblDivision = New-ThemedLabel -Text "Division:" -X 290 -Y 365
        $txtDivision = New-ThemedTextBox -Text $DirectoryObject.division -X 380 -Y 362 -Width 175

        $tpOrg.Controls.AddRange(@(
            $lblOrgTitle, $txtOrgTitle, $lblOrgDept, $txtOrgDept, $lblOrgComp, $txtOrgComp,
            $gbMgr, $lblReports, $lstReports,
            $lblEmpID, $txtEmpID, $lblEmpNum, $txtEmpNum,
            $lblEmpType, $txtEmpType, $lblDivision, $txtDivision
        ))
    }

    # =========================================================================
    # TAB: REMOTE DESKTOP SERVICES PROFILE
    # =========================================================================
    if ($tabs.TabPages.ContainsKey('Remote Desktop Services Profile')) {
        $tpRds = $tabs.TabPages['Remote Desktop Services Profile']

        $gbRdsProf = New-ThemedGroupBox -Title "Remote Desktop Services User Profile" -X 16 -Y 16 -Width 535 -Height 70
        $lblRdsProf = New-ThemedLabel -Text "User Profile Path:" -X 16 -Y 30
        $txtRdsProf = New-ThemedTextBox -Text $DirectoryObject.msTSProfilePath -X 140 -Y 27 -Width 375
        $gbRdsProf.Controls.AddRange(@($lblRdsProf, $txtRdsProf))

        $gbRdsHome = New-ThemedGroupBox -Title "Remote Desktop Services Home Directory" -X 16 -Y 95 -Width 535 -Height 105
        $rbRdsLocal = New-ThemedRadioButton -Text "Local path" -X 16 -Y 26 -Checked ($null -eq $DirectoryObject.msTSHomeDrive -or $DirectoryObject.msTSHomeDrive -eq "")
        $rdsLocalVal = $(if ($rbRdsLocal.Checked) { $DirectoryObject.msTSHomeDirectory } else { "" })
        $txtRdsLocal = New-ThemedTextBox -Text $rdsLocalVal -X 140 -Y 23 -Width 375
        $rbRdsNet = New-ThemedRadioButton -Text "Connect" -X 16 -Y 62 -Checked (-not $rbRdsLocal.Checked)
        $rdsDriveVal = $(if ($DirectoryObject.msTSHomeDrive) { $DirectoryObject.msTSHomeDrive } else { "Z:" })
        $cbRdsDrive = New-ThemedComboBox -Items @("D:", "E:", "F:", "G:", "H:", "Z:") -X 140 -Y 60 -Width 60 -Selected $rdsDriveVal
        $lblRdsTo = New-ThemedLabel -Text "To:" -X 210 -Y 62
        $rdsNetVal = $(if ($rbRdsNet.Checked) { $DirectoryObject.msTSHomeDirectory } else { "\\dc01\rdshome\$($DirectoryObject.sAMAccountName)" })
        $txtRdsNet = New-ThemedTextBox -Text $rdsNetVal -X 240 -Y 59 -Width 275
        $gbRdsHome.Controls.AddRange(@($rbRdsLocal, $txtRdsLocal, $rbRdsNet, $cbRdsDrive, $lblRdsTo, $txtRdsNet))

        $chkRdsDeny = New-ThemedCheckBox -Text "Deny this user permissions to log on to Remote Desktop Session Host server" -X 16 -Y 215 -Checked (-not [bool]$DirectoryObject.msTSAllowLogon)
        $tpRds.Controls.AddRange(@($gbRdsProf, $gbRdsHome, $chkRdsDeny))
    }

    # =========================================================================
    # TAB: COM+
    # =========================================================================
    if ($tabs.TabPages.ContainsKey('COM+')) {
        $tpCom = $tabs.TabPages['COM+']
        $gbCom = New-ThemedGroupBox -Title "COM+ Partition Set" -X 16 -Y 16 -Width 535 -Height 140
        $lblComDesc = New-ThemedLabel -Text "Select the COM+ partition set that this user account belongs to:" -X 16 -Y 28
        $cbComSet = New-ThemedComboBox -Items @("Default Partition Set", "Base Application Partition Set") -X 16 -Y 58 -Width 350 -Selected "Default Partition Set"
        $lblComStatus = New-ThemedLabel -Text "Active Directory user accounts belong to the default COM+ partition set." -X 16 -Y 95 -Secondary $true
        $gbCom.Controls.AddRange(@($lblComDesc, $cbComSet, $lblComStatus))
        $tpCom.Controls.Add($gbCom)
    }

    # =========================================================================
    # TAB: ENVIRONMENT
    # =========================================================================
    if ($tabs.TabPages.ContainsKey('Environment')) {
        $tpEnv = $tabs.TabPages['Environment']

        $gbStartProg = New-ThemedGroupBox -Title "Starting program" -X 16 -Y 16 -Width 535 -Height 125
        $chkStartProg = New-ThemedCheckBox -Text "Start the following program at logon:" -X 16 -Y 25 -Checked (-not [string]::IsNullOrEmpty($DirectoryObject.msTSInitialProgram))
        $lblProgName = New-ThemedLabel -Text "Program file name:" -X 36 -Y 56
        $txtProgName = New-ThemedTextBox -Text $DirectoryObject.msTSInitialProgram -X 160 -Y 53 -Width 355
        $lblStartIn = New-ThemedLabel -Text "Start in:" -X 36 -Y 90
        $txtStartIn = New-ThemedTextBox -Text $DirectoryObject.msTSWorkDirectory -X 160 -Y 87 -Width 355
        $gbStartProg.Controls.AddRange(@($chkStartProg, $lblProgName, $txtProgName, $lblStartIn, $txtStartIn))

        $gbDevices = New-ThemedGroupBox -Title "Client devices" -X 16 -Y 150 -Width 535 -Height 110
        $chkDrives = New-ThemedCheckBox -Text "Connect client drives at logon" -X 16 -Y 25 -Checked $true
        $chkPrinters = New-ThemedCheckBox -Text "Connect client printers at logon" -X 16 -Y 52 -Checked $true
        $chkDefPrinter = New-ThemedCheckBox -Text "Default to main client printer" -X 16 -Y 79 -Checked $true
        $gbDevices.Controls.AddRange(@($chkDrives, $chkPrinters, $chkDefPrinter))

        $tpEnv.Controls.AddRange(@($gbStartProg, $gbDevices))
    }

    # =========================================================================
    # TAB: SESSIONS
    # =========================================================================
    if ($tabs.TabPages.ContainsKey('Sessions')) {
        $tpSess = $tabs.TabPages['Sessions']

        $gbLimits = New-ThemedGroupBox -Title "Time limits" -X 16 -Y 16 -Width 535 -Height 135
        $lblDiscLim = New-ThemedLabel -Text "End a disconnected session:" -X 16 -Y 28
        $cbDiscLim = New-ThemedComboBox -Items @("Never", "1 minute", "5 minutes", "15 minutes", "30 minutes", "1 hour", "2 hours", "1 day") -X 210 -Y 25 -Width 180 -Selected "Never"
        $lblActLim = New-ThemedLabel -Text "Active session limit:" -X 16 -Y 62
        $cbActLim = New-ThemedComboBox -Items @("Never", "1 hour", "2 hours", "4 hours", "8 hours", "1 day", "2 days") -X 210 -Y 59 -Width 180 -Selected "Never"
        $lblIdleLim = New-ThemedLabel -Text "Idle session limit:" -X 16 -Y 96
        $cbIdleLim = New-ThemedComboBox -Items @("Never", "5 minutes", "10 minutes", "15 minutes", "30 minutes", "1 hour", "2 hours") -X 210 -Y 93 -Width 180 -Selected "Never"
        $gbLimits.Controls.AddRange(@($lblDiscLim, $cbDiscLim, $lblActLim, $cbActLim, $lblIdleLim, $cbIdleLim))

        $gbBroken = New-ThemedGroupBox -Title "When session limit is reached or connection is broken:" -X 16 -Y 160 -Width 535 -Height 65
        $rbDisc = New-ThemedRadioButton -Text "Disconnect from session" -X 20 -Y 26 -Checked $true
        $rbEnd = New-ThemedRadioButton -Text "End session" -X 240 -Y 26 -Checked $false
        $gbBroken.Controls.AddRange(@($rbDisc, $rbEnd))

        $gbRecon = New-ThemedGroupBox -Title "Allow reconnection:" -X 16 -Y 235 -Width 535 -Height 65
        $rbRecAny = New-ThemedRadioButton -Text "From any client" -X 20 -Y 26 -Checked $true
        $rbRecPrev = New-ThemedRadioButton -Text "From previous client only" -X 240 -Y 26 -Checked $false
        $gbRecon.Controls.AddRange(@($rbRecAny, $rbRecPrev))

        $tpSess.Controls.AddRange(@($gbLimits, $gbBroken, $gbRecon))
    }

    # =========================================================================
    # TAB: REMOTE CONTROL
    # =========================================================================
    if ($tabs.TabPages.ContainsKey('Remote control')) {
        $tpRc = $tabs.TabPages['Remote control']

        $gbRc = New-ThemedGroupBox -Title "Remote Control" -X 16 -Y 16 -Width 535 -Height 95
        $chkRcEnable = New-ThemedCheckBox -Text "Enable remote control" -X 16 -Y 28 -Checked ([bool]$DirectoryObject.msTSRemoteControl)
        $chkRcRequire = New-ThemedCheckBox -Text "Require user's permission" -X 16 -Y 58 -Checked $true
        $gbRc.Controls.AddRange(@($chkRcEnable, $chkRcRequire))

        $gbRcLevel = New-ThemedGroupBox -Title "Level of control" -X 16 -Y 120 -Width 535 -Height 85
        $rbRcView = New-ThemedRadioButton -Text "View the session" -X 20 -Y 28 -Checked $false
        $rbRcInteract = New-ThemedRadioButton -Text "Interact with the session" -X 20 -Y 54 -Checked $true
        $gbRcLevel.Controls.AddRange(@($rbRcView, $rbRcInteract))

        $tpRc.Controls.AddRange(@($gbRc, $gbRcLevel))
    }

    # =========================================================================
    # TAB: SECURITY
    # =========================================================================
    if ($tabs.TabPages.ContainsKey('Security')) {
        $tpSec = $tabs.TabPages['Security']

        $lblSecUsers = New-ThemedLabel -Text "Group or user names:" -X 16 -Y 16
        $lstSecUsers = New-Object System.Windows.Forms.ListBox
        $lstSecUsers.Location = New-Object System.Drawing.Point(16, 38)
        $lstSecUsers.Size = New-Object System.Drawing.Size(540, 110)
        $lstSecUsers.BackColor = $Script:Theme.InputBg
        $lstSecUsers.ForeColor = $Script:Theme.TextPrimary
        $lstSecUsers.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
        $lstSecUsers.Font = $Script:FontBody
        $secPrincipals = @("SELF", "Domain Admins (CORP\Domain Admins)", "Enterprise Admins (CORP\Enterprise Admins)", "SYSTEM", "Account Operators (CORP\Account Operators)", "Authenticated Users", "Key Admins")
        foreach ($p in $secPrincipals) { $null = $lstSecUsers.Items.Add($p) }
        $lstSecUsers.SelectedIndex = 0

        $lblSecPerms = New-ThemedLabel -Text "Permissions for selected principal:" -X 16 -Y 160
        $clbPerms = New-Object System.Windows.Forms.CheckedListBox
        $clbPerms.Location = New-Object System.Drawing.Point(16, 182)
        $clbPerms.Size = New-Object System.Drawing.Size(540, 150)
        $clbPerms.BackColor = $Script:Theme.InputBg
        $clbPerms.ForeColor = $Script:Theme.TextPrimary
        $clbPerms.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
        $clbPerms.Font = $Script:FontBody
        $perms = @("Full Control", "Read", "Write", "Reset Password", "Change Password", "Send As", "Receive As", "Read all properties", "Write all properties")
        foreach ($perm in $perms) {
            $null = $clbPerms.Items.Add($perm, ($perm -in @("Read", "Change Password", "Read all properties")))
        }

        $btnSecAdv = New-ThemedButton -Text "Advanced" -X 470 -Y 340 -Width 85

        $tpSec.Controls.AddRange(@($lblSecUsers, $lstSecUsers, $lblSecPerms, $clbPerms, $btnSecAdv))
    }

    # =========================================================================
    # TAB: PUBLISHED CERTIFICATES
    # =========================================================================
    if ($tabs.TabPages.ContainsKey('Published Certificates')) {
        $tpCert = $tabs.TabPages['Published Certificates']

        $lblCertHdr = New-ThemedLabel -Text "List of X.509 certificates published to this user account:" -X 16 -Y 16
        $lvCerts = New-Object System.Windows.Forms.ListView
        $lvCerts.Location = New-Object System.Drawing.Point(16, 40)
        $lvCerts.Size = New-Object System.Drawing.Size(540, 240)
        $lvCerts.View = [System.Windows.Forms.View]::Details
        $lvCerts.FullRowSelect = $true
        $lvCerts.GridLines = $true
        $lvCerts.BackColor = $Script:Theme.InputBg
        $lvCerts.ForeColor = $Script:Theme.TextPrimary
        $lvCerts.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
        $lvCerts.Font = $Script:FontBody
        $null = $lvCerts.Columns.Add("Issued To", 160)
        $null = $lvCerts.Columns.Add("Issued By", 160)
        $null = $lvCerts.Columns.Add("Purpose", 120)
        $null = $lvCerts.Columns.Add("Expiration Date", 90)

        if ($DirectoryObject.userCertificate) {
            foreach ($cert in $DirectoryObject.userCertificate) {
                $cItem = New-Object System.Windows.Forms.ListViewItem($DirectoryObject.displayName)
                $null = $cItem.SubItems.Add("Contoso Corporate CA")
                $null = $cItem.SubItems.Add("Client Authentication")
                $null = $cItem.SubItems.Add("2028-10-15")
                $null = $lvCerts.Items.Add($cItem)
            }
        }

        $btnViewCert = New-ThemedButton -Text "View Certificate..." -X 16 -Y 290 -Width 130
        $btnAddCert = New-ThemedButton -Text "Add..." -X 300 -Y 290 -Width 80
        $btnRemCert = New-ThemedButton -Text "Remove" -X 385 -Y 290 -Width 80
        $btnCopyCert = New-ThemedButton -Text "Copy to File..." -X 470 -Y 290 -Width 85

        $tpCert.Controls.AddRange(@($lblCertHdr, $lvCerts, $btnViewCert, $btnAddCert, $btnRemCert, $btnCopyCert))
    }

    # =========================================================================
    # TAB: MEMBER OF
    # =========================================================================
    if ($tabs.TabPages.ContainsKey('Member Of')) {
        $tpMem = $tabs.TabPages['Member Of']

        $lblMemHdr = New-ThemedLabel -Text "Member of:" -X 16 -Y 16
        $lvGroups = New-Object System.Windows.Forms.ListView
        $lvGroups.Location = New-Object System.Drawing.Point(16, 40)
        $lvGroups.Size = New-Object System.Drawing.Size(540, 240)
        $lvGroups.View = [System.Windows.Forms.View]::Details
        $lvGroups.FullRowSelect = $true
        $lvGroups.GridLines = $true
        $lvGroups.BackColor = $Script:Theme.InputBg
        $lvGroups.ForeColor = $Script:Theme.TextPrimary
        $lvGroups.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
        $lvGroups.Font = $Script:FontBody
        $null = $lvGroups.Columns.Add("Name", 220)
        $null = $lvGroups.Columns.Add("Active Directory Folder", 300)

        if ($DirectoryObject.MemberOf) {
            foreach ($grp in $DirectoryObject.MemberOf) {
                $grpName = $(if ($grp -like "CN=*") { ($grp -split ",")[0] -replace "^CN=","" } else { "$grp" })
                $grpFolder = $(if ($grp -like "CN=*") { ($grp -split ",",2)[1] } else { "corp.contoso.local/Users" })
                $gItem = New-Object System.Windows.Forms.ListViewItem($grpName)
                $null = $gItem.SubItems.Add($grpFolder)
                $gItem.Tag = $grp
                $null = $lvGroups.Items.Add($gItem)
            }
        }

        $lblPrimary = New-ThemedLabel -Text "Primary group: Domain Users" -X 16 -Y 290 -Secondary $true
        $btnAddGrp = New-ThemedButton -Text "Add..." -X 295 -Y 290 -Width 80
        $btnRemGrp = New-ThemedButton -Text "Remove" -X 380 -Y 290 -Width 80
        $btnSetPrim = New-ThemedButton -Text "Set Primary Group" -X 465 -Y 290 -Width 90

        $btnRemGrp.Add_Click({
            if ($lvGroups.SelectedItems.Count -gt 0) {
                $remItem = $lvGroups.SelectedItems[0]
                $lvGroups.Items.Remove($remItem)
            }
        })

        $tpMem.Controls.AddRange(@($lblMemHdr, $lvGroups, $lblPrimary, $btnAddGrp, $btnRemGrp, $btnSetPrim))
    }

    # =========================================================================
    # TAB: MEMBERS (for Groups)
    # =========================================================================
    if ($tabs.TabPages.ContainsKey('Members')) {
        $tpMembers = $tabs.TabPages['Members']
        $lblMembersHdr = New-ThemedLabel -Text "Members:" -X 16 -Y 16
        $lvMembers = New-Object System.Windows.Forms.ListView
        $lvMembers.Location = New-Object System.Drawing.Point(16, 40)
        $lvMembers.Size = New-Object System.Drawing.Size(540, 240)
        $lvMembers.View = [System.Windows.Forms.View]::Details
        $lvMembers.FullRowSelect = $true
        $lvMembers.GridLines = $true
        $lvMembers.BackColor = $Script:Theme.InputBg
        $lvMembers.ForeColor = $Script:Theme.TextPrimary
        $lvMembers.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
        $lvMembers.Font = $Script:FontBody
        $null = $lvMembers.Columns.Add("Name", 220)
        $null = $lvMembers.Columns.Add("Active Directory Folder", 300)

        # Look up demo users who belong to this group
        if ($Script:DemoStore.Objects) {
            foreach ($usr in $Script:DemoStore.Objects) {
                if ($usr.MemberOf -and ($usr.MemberOf -contains $DirectoryObject.Name -or $usr.MemberOf -contains $DirectoryObject.DistinguishedName)) {
                    $mItem = New-Object System.Windows.Forms.ListViewItem($usr.Name)
                    $null = $mItem.SubItems.Add($usr.ParentDN)
                    $null = $lvMembers.Items.Add($mItem)
                }
            }
        }

        $btnAddMember = New-ThemedButton -Text "Add..." -X 380 -Y 290 -Width 80
        $btnRemMember = New-ThemedButton -Text "Remove" -X 470 -Y 290 -Width 85
        $btnRemMember.Add_Click({
            if ($lvMembers.SelectedItems.Count -gt 0) {
                $lvMembers.Items.Remove($lvMembers.SelectedItems[0])
            }
        })
        $tpMembers.Controls.AddRange(@($lblMembersHdr, $lvMembers, $btnAddMember, $btnRemMember))
    }

    # =========================================================================
    # TAB: MANAGED BY (for Groups and Computers)
    # =========================================================================
    if ($tabs.TabPages.ContainsKey('Managed By')) {
        $tpMgrBy = $tabs.TabPages['Managed By']
        $gbMgrInfo = New-ThemedGroupBox -Title "Manager" -X 16 -Y 16 -Width 540 -Height 100
        $lblMgrByName = New-ThemedLabel -Text "Name:" -X 16 -Y 28
        $txtMgrByName = New-ThemedTextBox -Text $DirectoryObject.manager -X 70 -Y 25 -Width 450 -ReadOnly $true
        $btnMgrByChange = New-ThemedButton -Text "Change..." -X 350 -Y 60 -Width 80
        $btnMgrByClear = New-ThemedButton -Text "Clear" -X 440 -Y 60 -Width 80
        $btnMgrByClear.Add_Click({ $txtMgrByName.Text = "" })
        $gbMgrInfo.Controls.AddRange(@($lblMgrByName, $txtMgrByName, $btnMgrByChange, $btnMgrByClear))

        $mgrObj = $null
        if ($DirectoryObject.manager -and $Script:DemoStore.Objects) {
            $mgrObj = $Script:DemoStore.Objects | Where-Object { $_.DistinguishedName -eq $DirectoryObject.manager -or $_.Name -eq $DirectoryObject.manager } | Select-Object -First 1
        }
        $mgrOff = $(if ($mgrObj) { $mgrObj.office } else { "" })
        $mgrStr = $(if ($mgrObj) { $mgrObj.streetAddress } else { "" })
        $mgrCit = $(if ($mgrObj) { $mgrObj.l } else { "" })
        $mgrTel = $(if ($mgrObj) { $mgrObj.telephoneNumber } else { "" })

        $lblMgrOffice = New-ThemedLabel -Text "Office:" -X 16 -Y 130
        $txtMgrOffice = New-ThemedTextBox -Text $mgrOff -X 130 -Y 127 -Width 420 -ReadOnly $true
        $lblMgrStreet = New-ThemedLabel -Text "Street:" -X 16 -Y 165
        $txtMgrStreet = New-ThemedTextBox -Text $mgrStr -X 130 -Y 162 -Width 420 -ReadOnly $true
        $lblMgrCity = New-ThemedLabel -Text "City:" -X 16 -Y 200
        $txtMgrCity = New-ThemedTextBox -Text $mgrCit -X 130 -Y 197 -Width 420 -ReadOnly $true
        $lblMgrPhone = New-ThemedLabel -Text "Telephone:" -X 16 -Y 235
        $txtMgrPhone = New-ThemedTextBox -Text $mgrTel -X 130 -Y 232 -Width 420 -ReadOnly $true

        $tpMgrBy.Controls.AddRange(@($gbMgrInfo, $lblMgrOffice, $txtMgrOffice, $lblMgrStreet, $txtMgrStreet, $lblMgrCity, $txtMgrCity, $lblMgrPhone, $txtMgrPhone))
    }

    # =========================================================================
    # TAB: OPERATING SYSTEM (for Computers)
    # =========================================================================
    if ($tabs.TabPages.ContainsKey('Operating System')) {
        $tpOs = $tabs.TabPages['Operating System']
        $lblOsName = New-ThemedLabel -Text "Name:" -X 16 -Y 20
        $txtOsName = New-ThemedTextBox -Text $DirectoryObject.OperatingSystem -X 130 -Y 17 -Width 420 -ReadOnly $true
        $lblOsVer = New-ThemedLabel -Text "Version:" -X 16 -Y 55
        $txtOsVer = New-ThemedTextBox -Text $DirectoryObject.OperatingSystemVersion -X 130 -Y 52 -Width 420 -ReadOnly $true
        $lblOsSp = New-ThemedLabel -Text "Service pack:" -X 16 -Y 90
        $txtOsSp = New-ThemedTextBox -Text $DirectoryObject.OperatingSystemServicePack -X 130 -Y 87 -Width 420 -ReadOnly $true
        $tpOs.Controls.AddRange(@($lblOsName, $txtOsName, $lblOsVer, $txtOsVer, $lblOsSp, $txtOsSp))
    }

    # =========================================================================
    # TAB: DELEGATION (for Computers)
    # =========================================================================
    if ($tabs.TabPages.ContainsKey('Delegation')) {
        $tpDel = $tabs.TabPages['Delegation']
        $lblDelDesc = New-ThemedLabel -Text "Delegation is a security-sensitive operation, which allows services to act on behalf of another user." -X 16 -Y 16
        $rbDelNone = New-ThemedRadioButton -Text "Do not trust this computer for delegation" -X 20 -Y 50 -Checked $true
        $rbDelAny = New-ThemedRadioButton -Text "Trust this computer for delegation to any service (Kerberos only)" -X 20 -Y 80
        $rbDelSpecific = New-ThemedRadioButton -Text "Trust this computer for delegation to specified services only" -X 20 -Y 110
        $tpDel.Controls.AddRange(@($lblDelDesc, $rbDelNone, $rbDelAny, $rbDelSpecific))
    }

    # =========================================================================
    # TAB: LOCATION (for Computers)
    # =========================================================================
    if ($tabs.TabPages.ContainsKey('Location')) {
        $tpLoc = $tabs.TabPages['Location']
        $lblLoc = New-ThemedLabel -Text "Location:" -X 16 -Y 20
        $txtCompLoc = New-ThemedTextBox -Text $DirectoryObject.Location -X 100 -Y 17 -Width 360
        $btnLocBrowse = New-ThemedButton -Text "Browse..." -X 470 -Y 16 -Width 85
        $tpLoc.Controls.AddRange(@($lblLoc, $txtCompLoc, $btnLocBrowse))
    }

    # =========================================================================
    # TAB: PASSWORD REPLICATION
    # =========================================================================
    if ($tabs.TabPages.ContainsKey('Password Replication')) {
        $tpPso = $tabs.TabPages['Password Replication']

        $gbPso = New-ThemedGroupBox -Title "Resultant Password Settings Object (PSO)" -X 16 -Y 16 -Width 535 -Height 280
        $lblPsoName = New-ThemedLabel -Text "Applied Policy: Default Domain Password Policy" -X 16 -Y 28 -Bold $true
        $lblPso1 = New-ThemedLabel -Text "Minimum password length: 12 characters" -X 16 -Y 60
        $lblPso2 = New-ThemedLabel -Text "Password history: 24 passwords remembered" -X 16 -Y 88
        $lblPso3 = New-ThemedLabel -Text "Minimum password age: 1 day" -X 16 -Y 116
        $lblPso4 = New-ThemedLabel -Text "Maximum password age: 60 days" -X 16 -Y 144
        $lblPso5 = New-ThemedLabel -Text "Account lockout threshold: 5 failed attempts" -X 16 -Y 172
        $lblPso6 = New-ThemedLabel -Text "Lockout duration: 30 minutes" -X 16 -Y 200
        $lblPso7 = New-ThemedLabel -Text "Reset lockout counter after: 30 minutes" -X 16 -Y 228
        $lblPso8 = New-ThemedLabel -Text "Password complexity: Enabled" -X 16 -Y 254 -Bold $true
        $gbPso.Controls.AddRange(@($lblPsoName, $lblPso1, $lblPso2, $lblPso3, $lblPso4, $lblPso5, $lblPso6, $lblPso7, $lblPso8))

        $tpPso.Controls.Add($gbPso)
    }

    # =========================================================================
    # TAB: DIAL-IN
    # =========================================================================
    if ($tabs.TabPages.ContainsKey('Dial-in')) {
        $tpDial = $tabs.TabPages['Dial-in']

        $gbDialPerm = New-ThemedGroupBox -Title "Network Access Permission" -X 16 -Y 16 -Width 535 -Height 100
        $rbDialAllow = New-ThemedRadioButton -Text "Allow access" -X 20 -Y 25 -Checked ($DirectoryObject.msNPAllowDialin -eq $true)
        $rbDialDeny = New-ThemedRadioButton -Text "Deny access" -X 20 -Y 48 -Checked ($DirectoryObject.msNPAllowDialin -eq $false)
        $rbDialNPS = New-ThemedRadioButton -Text "Control access through NPS Network Policy" -X 20 -Y 71 -Checked ($DirectoryObject.msNPAllowDialin -ne $true -and $DirectoryObject.msNPAllowDialin -ne $false)
        $gbDialPerm.Controls.AddRange(@($rbDialAllow, $rbDialDeny, $rbDialNPS))

        $chkCallerId = New-ThemedCheckBox -Text "Verify Caller-ID:" -X 16 -Y 130 -Checked (-not [string]::IsNullOrEmpty($DirectoryObject.msNPCallingStationID))
        $txtCallerId = New-ThemedTextBox -Text $DirectoryObject.msNPCallingStationID -X 140 -Y 127 -Width 240

        $gbCallback = New-ThemedGroupBox -Title "Callback Options" -X 16 -Y 165 -Width 535 -Height 100
        $rbCbNone = New-ThemedRadioButton -Text "No Callback" -X 20 -Y 25 -Checked $true
        $rbCbCaller = New-ThemedRadioButton -Text "Set by Caller (Routing and Remote Access only)" -X 20 -Y 48
        $rbCbAlways = New-ThemedRadioButton -Text "Always Callback to:" -X 20 -Y 71
        $txtCbNum = New-ThemedTextBox -Text "" -X 170 -Y 68 -Width 200
        $gbCallback.Controls.AddRange(@($rbCbNone, $rbCbCaller, $rbCbAlways, $txtCbNum))

        $gbStaticIP = New-ThemedGroupBox -Title "Assign a Static IP Address" -X 16 -Y 275 -Width 535 -Height 65
        $chkStaticIP = New-ThemedCheckBox -Text "Assign Static IP:" -X 16 -Y 26 -Checked (-not [string]::IsNullOrEmpty($DirectoryObject.msRADIUSFramedIPAddress))
        $txtStaticIP = New-ThemedTextBox -Text $DirectoryObject.msRADIUSFramedIPAddress -X 150 -Y 23 -Width 200
        $gbStaticIP.Controls.AddRange(@($chkStaticIP, $txtStaticIP))

        $tpDial.Controls.AddRange(@($gbDialPerm, $chkCallerId, $txtCallerId, $gbCallback, $gbStaticIP))
    }

    # =========================================================================
    # TAB: OBJECT
    # =========================================================================
    if ($tabs.TabPages.ContainsKey('Object')) {
        $tpObj = $tabs.TabPages['Object']

        $lblObjDn = New-ThemedLabel -Text "Distinguished Name:" -X 16 -Y 18
        $txtObjDn = New-ThemedTextBox -Text $DirectoryObject.DistinguishedName -X 16 -Y 40 -Width 540 -Height 50 -Multiline $true -ReadOnly $true

        $lblObjClass = New-ThemedLabel -Text "Object class:" -X 16 -Y 105
        $txtObjClass = New-ThemedTextBox -Text $DirectoryObject.ObjectClass -X 120 -Y 102 -Width 435 -ReadOnly $true

        $lblObjCreated = New-ThemedLabel -Text "Created:" -X 16 -Y 145
        $txtObjCreated = New-ThemedTextBox -Text $DirectoryObject.whenCreated -X 120 -Y 142 -Width 435 -ReadOnly $true

        $lblObjChanged = New-ThemedLabel -Text "Modified:" -X 16 -Y 185
        $txtObjChanged = New-ThemedTextBox -Text $DirectoryObject.whenChanged -X 120 -Y 182 -Width 435 -ReadOnly $true

        $lblObjUsnC = New-ThemedLabel -Text "USN Created:" -X 16 -Y 225
        $txtObjUsnC = New-ThemedTextBox -Text $DirectoryObject.uSNCreated -X 120 -Y 222 -Width 180 -ReadOnly $true

        $lblObjUsnM = New-ThemedLabel -Text "USN Modified:" -X 315 -Y 225
        $txtObjUsnM = New-ThemedTextBox -Text $DirectoryObject.uSNChanged -X 405 -Y 222 -Width 150 -ReadOnly $true

        $tpObj.Controls.AddRange(@(
            $lblObjDn, $txtObjDn, $lblObjClass, $txtObjClass,
            $lblObjCreated, $txtObjCreated, $lblObjChanged, $txtObjChanged,
            $lblObjUsnC, $txtObjUsnC, $lblObjUsnM, $txtObjUsnM
        ))
    }

    # =========================================================================
    # TAB: ATTRIBUTE EDITOR
    # =========================================================================
    $allLdapDefs = @(
        @{ Name="accountExpires"; Syntax="Large Integer/File Time"; Field="AccountExpires" },
        @{ Name="adminCount"; Syntax="Integer"; Field="adminCount" },
        @{ Name="badPasswordTime"; Syntax="Large Integer/File Time"; Field="badPasswordTime" },
        @{ Name="badPwdCount"; Syntax="Integer"; Field="badPwdCount" },
        @{ Name="c"; Syntax="Unicode String"; Field="c" },
        @{ Name="cn"; Syntax="Unicode String"; Field="displayName" },
        @{ Name="co"; Syntax="Unicode String"; Field="co" },
        @{ Name="codePage"; Syntax="Integer"; Field="codePage" },
        @{ Name="comment"; Syntax="Unicode String"; Field="comment" },
        @{ Name="company"; Syntax="Unicode String"; Field="company" },
        @{ Name="countryCode"; Syntax="Integer"; Field="countryCode" },
        @{ Name="department"; Syntax="Unicode String"; Field="department" },
        @{ Name="description"; Syntax="Unicode String"; Field="Description" },
        @{ Name="directReports"; Syntax="Distinguished Name (Multi)"; Field="directReports" },
        @{ Name="displayName"; Syntax="Unicode String"; Field="displayName" },
        @{ Name="distinguishedName"; Syntax="Distinguished Name"; Field="DistinguishedName" },
        @{ Name="division"; Syntax="Unicode String"; Field="division" },
        @{ Name="employeeID"; Syntax="Unicode String"; Field="employeeID" },
        @{ Name="employeeNumber"; Syntax="Unicode String"; Field="employeeNumber" },
        @{ Name="employeeType"; Syntax="Unicode String"; Field="employeeType" },
        @{ Name="facsimileTelephoneNumber"; Syntax="Unicode String"; Field="facsimileTelephoneNumber" },
        @{ Name="givenName"; Syntax="Unicode String"; Field="givenName" },
        @{ Name="homeDirectory"; Syntax="Unicode String"; Field="homeDirectory" },
        @{ Name="homeDrive"; Syntax="Unicode String"; Field="homeDrive" },
        @{ Name="homePhone"; Syntax="Unicode String"; Field="homePhone" },
        @{ Name="info"; Syntax="Unicode String (Multi-line)"; Field="info" },
        @{ Name="initials"; Syntax="Unicode String"; Field="initials" },
        @{ Name="instanceType"; Syntax="Integer"; Field="instanceType" },
        @{ Name="ipPhone"; Syntax="Unicode String"; Field="ipPhone" },
        @{ Name="lastLogon"; Syntax="Large Integer/File Time"; Field="lastLogon" },
        @{ Name="lastLogonTimestamp"; Syntax="Large Integer/File Time"; Field="lastLogonTimestamp" },
        @{ Name="lockoutTime"; Syntax="Large Integer/File Time"; Field="lockoutTime" },
        @{ Name="logonCount"; Syntax="Integer"; Field="logonCount" },
        @{ Name="mail"; Syntax="Unicode String"; Field="mail" },
        @{ Name="mailNickname"; Syntax="Unicode String"; Field="mailNickname" },
        @{ Name="manager"; Syntax="Distinguished Name"; Field="manager" },
        @{ Name="memberOf"; Syntax="Distinguished Name (Multi)"; Field="MemberOf" },
        @{ Name="mobile"; Syntax="Unicode String"; Field="mobile" },
        @{ Name="msDS-ResultantPSO"; Syntax="Distinguished Name"; Field="msDSResultantPSO" },
        @{ Name="msNPAllowDialin"; Syntax="Boolean"; Field="msNPAllowDialin" },
        @{ Name="msNPCallingStationID"; Syntax="Unicode String"; Field="msNPCallingStationID" },
        @{ Name="msRADIUSFramedIPAddress"; Syntax="Unicode String"; Field="msRADIUSFramedIPAddress" },
        @{ Name="msTSAllowLogon"; Syntax="Boolean"; Field="msTSAllowLogon" },
        @{ Name="msTSHomeDirectory"; Syntax="Unicode String"; Field="msTSHomeDirectory" },
        @{ Name="msTSHomeDrive"; Syntax="Unicode String"; Field="msTSHomeDrive" },
        @{ Name="msTSInitialProgram"; Syntax="Unicode String"; Field="msTSInitialProgram" },
        @{ Name="msTSProfilePath"; Syntax="Unicode String"; Field="msTSProfilePath" },
        @{ Name="msTSRemoteControl"; Syntax="Integer"; Field="msTSRemoteControl" },
        @{ Name="msTSWorkDirectory"; Syntax="Unicode String"; Field="msTSWorkDirectory" },
        @{ Name="name"; Syntax="Unicode String"; Field="Name" },
        @{ Name="objectCategory"; Syntax="Distinguished Name"; Field="objectCategory" },
        @{ Name="objectClass"; Syntax="Unicode String (Multi)"; Field="ObjectClass" },
        @{ Name="objectGUID"; Syntax="Octet String / GUID"; Field="objectGUID" },
        @{ Name="objectSid"; Syntax="Security Identifier (SID)"; Field="objectSid" },
        @{ Name="otherTelephone"; Syntax="Unicode String (Multi)"; Field="otherTelephone" },
        @{ Name="pager"; Syntax="Unicode String"; Field="pager" },
        @{ Name="physicalDeliveryOfficeName"; Syntax="Unicode String"; Field="office" },
        @{ Name="postalCode"; Syntax="Unicode String"; Field="postalCode" },
        @{ Name="postOfficeBox"; Syntax="Unicode String"; Field="postOfficeBox" },
        @{ Name="primaryGroupID"; Syntax="Integer"; Field="primaryGroupID" },
        @{ Name="profilePath"; Syntax="Unicode String"; Field="profilePath" },
        @{ Name="proxyAddresses"; Syntax="Unicode String (Multi)"; Field="proxyAddresses" },
        @{ Name="pwdLastSet"; Syntax="Large Integer/File Time"; Field="pwdLastSet" },
        @{ Name="sAMAccountName"; Syntax="Unicode String"; Field="sAMAccountName" },
        @{ Name="sAMAccountType"; Syntax="Integer"; Field="sAMAccountType" },
        @{ Name="scriptPath"; Syntax="Unicode String"; Field="scriptPath" },
        @{ Name="sn"; Syntax="Unicode String"; Field="sn" },
        @{ Name="st"; Syntax="Unicode String"; Field="st" },
        @{ Name="streetAddress"; Syntax="Unicode String"; Field="streetAddress" },
        @{ Name="telephoneNumber"; Syntax="Unicode String"; Field="telephoneNumber" },
        @{ Name="title"; Syntax="Unicode String"; Field="title" },
        @{ Name="userAccountControl"; Syntax="Integer"; Field="userAccountControl" },
        @{ Name="userCertificate"; Syntax="Octet String / X.509"; Field="userCertificate" },
        @{ Name="userPrincipalName"; Syntax="Unicode String"; Field="userPrincipalName" },
        @{ Name="userWorkstations"; Syntax="Unicode String"; Field="userWorkstations" },
        @{ Name="uSNCreated"; Syntax="Large Integer"; Field="uSNCreated" },
        @{ Name="uSNChanged"; Syntax="Large Integer"; Field="uSNChanged" },
        @{ Name="whenChanged"; Syntax="Generalized Time"; Field="whenChanged" },
        @{ Name="whenCreated"; Syntax="Generalized Time"; Field="whenCreated" },
        @{ Name="wWWHomePage"; Syntax="Unicode String"; Field="wWWHomePage" }
    )

    $tpAttr = $tabs.TabPages['Attribute Editor']
    $lblAttrFilt = New-ThemedLabel -Text "Filter:" -X 16 -Y 16
    $txtAttrFilt = New-ThemedTextBox -Text "" -X 60 -Y 13 -Width 260
    $btnAttrToggle = New-ThemedButton -Text "Show only with values" -X 330 -Y 11 -Width 225

    $lvAttr = New-Object System.Windows.Forms.ListView
    $lvAttr.Location = New-Object System.Drawing.Point(16, 46)
    $lvAttr.Size = New-Object System.Drawing.Size(540, 480)
    $lvAttr.View = [System.Windows.Forms.View]::Details
    $lvAttr.FullRowSelect = $true
    $lvAttr.GridLines = $true
    $lvAttr.MultiSelect = $false
    $lvAttr.BackColor = $Script:Theme.InputBg
    $lvAttr.ForeColor = $Script:Theme.TextPrimary
    $lvAttr.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $lvAttr.Font = $Script:FontBody
    $null = $lvAttr.Columns.Add("Attribute", 175)
    $null = $lvAttr.Columns.Add("Syntax", 115)
    $null = $lvAttr.Columns.Add("Value", 240)

    $btnEditAttr = New-ThemedButton -Text "Edit..." -X 470 -Y 535 -Width 85

    # Attribute Editor State
    $Script:AttrFilterOnlyValues = $false
    $Script:AttrSearchText = ""

    # Initialize Attribute Editor List
    $attrContext = @{
        ListView = $lvAttr
        Defs = $allLdapDefs
        TargetObject = $DirectoryObject
        TxtFilter = $txtAttrFilt
    }
    $txtAttrFilt.Tag = $attrContext
    $btnAttrToggle.Tag = $attrContext

    Update-AttributeListView -ListView $lvAttr -FilterText "" -OnlyValues $Script:AttrFilterOnlyValues -LdapDefs $allLdapDefs -TargetObject $DirectoryObject

    $txtAttrFilt.Add_TextChanged({
        param($sender, $e)
        $ctx = $sender.Tag
        if ($ctx) {
            Update-AttributeListView -ListView $ctx.ListView -FilterText $sender.Text.Trim() -OnlyValues $Script:AttrFilterOnlyValues -LdapDefs $ctx.Defs -TargetObject $ctx.TargetObject
        }
    })

    $btnAttrToggle.Add_Click({
        param($sender, $e)
        $ctx = $sender.Tag
        $Script:AttrFilterOnlyValues = -not $Script:AttrFilterOnlyValues
        if ($Script:AttrFilterOnlyValues) { $sender.Text = "Show all attributes" } else { $sender.Text = "Show only with values" }
        if ($ctx) {
            $fText = if ($ctx.TxtFilter) { $ctx.TxtFilter.Text.Trim() } else { "" }
            Update-AttributeListView -ListView $ctx.ListView -FilterText $fText -OnlyValues $Script:AttrFilterOnlyValues -LdapDefs $ctx.Defs -TargetObject $ctx.TargetObject
        }
    })

    $HandleEditAttr = {
        if ($lvAttr.SelectedItems.Count -gt 0) {
            $selTag = $lvAttr.SelectedItems[0].Tag
            $def = $selTag.Def
            $editRes = Show-AttributeEditorDialog -AttributeName $def.Name -Syntax $def.Syntax -CurrentValue $DirectoryObject.$($def.Field)
            if ($editRes.Changed) {
                $DirectoryObject.$($def.Field) = $editRes.Value
                Update-AttributeListView -ListView $lvAttr -FilterText $txtAttrFilt.Text.Trim() -OnlyValues $Script:AttrFilterOnlyValues -LdapDefs $allLdapDefs -TargetObject $DirectoryObject
            }
        }
    }

    $btnEditAttr.Add_Click($HandleEditAttr)
    $lvAttr.Add_DoubleClick($HandleEditAttr)

    $tpAttr.Controls.AddRange(@($lblAttrFilt, $txtAttrFilt, $btnAttrToggle, $lvAttr, $btnEditAttr))

    # Dialog Action Buttons
    $btnSave = New-ThemedButton -Text "OK" -X 315 -Y 640 -Width 85 -Primary $true
    $btnCancel = New-ThemedButton -Text "Cancel" -X 410 -Y 640 -Width 85 -Primary $false
    $btnApply = New-ThemedButton -Text "Apply" -X 505 -Y 640 -Width 85 -Primary $false

    $btnSave.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.AcceptButton = $btnSave
    $dlg.CancelButton = $btnCancel

    # Shared Save Logic for Apply and OK
    $SaveAction = {
        if ($Script:IsLiveAD) {
            if ($isUser) {
                try {
                    Set-ADUser -Identity $DirectoryObject.DistinguishedName `
                        -DisplayName $txtDisp.Text `
                        -Description $txtDesc.Text `
                        -Office $txtOffice.Text `
                        -OfficePhone $txtPhone.Text `
                        -EmailAddress $txtMail.Text `
                        -HomePage $txtWeb.Text `
                        -Title $txtOrgTitle.Text `
                        -Department $txtOrgDept.Text `
                        -Company $txtOrgComp.Text `
                        -StreetAddress $txtStreet.Text `
                        -POBox $txtPOBox.Text `
                        -City $txtCity.Text `
                        -State $txtState.Text `
                        -PostalCode $txtZip.Text `
                        -Country $txtCountry.Text `
                        -Enabled (-not $chkDisabled.Checked) `
                        -ChangePasswordAtLogon $chkMustChange.Checked `
                        -PasswordNeverExpires $chkPassNever.Checked `
                        -CannotChangePassword $chkCantChange.Checked
                    if ($chkUnlock.Checked) { Unlock-ADAccount -Identity $DirectoryObject.DistinguishedName }
                } catch {
                    [System.Windows.Forms.MessageBox]::Show("Error saving user to Active Directory: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                }
            } elseif ($isGroup) {
                try {
                    if ($txtGrpDesc) { Set-ADGroup -Identity $DirectoryObject.DistinguishedName -Description $txtGrpDesc.Text }
                } catch {
                    [System.Windows.Forms.MessageBox]::Show("Error saving group to Active Directory: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                }
            } elseif ($isComputer) {
                try {
                    if ($txtCompDesc) { Set-ADComputer -Identity $DirectoryObject.DistinguishedName -Description $txtCompDesc.Text }
                } catch {
                    [System.Windows.Forms.MessageBox]::Show("Error saving computer to Active Directory: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                }
            }
        } else {
            # Demo Mode persistence
            if ($isUser) {
                $DirectoryObject.givenName = $txtFirst.Text
                $DirectoryObject.initials = $txtInit.Text
                $DirectoryObject.sn = $txtLast.Text
                $DirectoryObject.displayName = $txtDisp.Text
                $DirectoryObject.Name = $txtDisp.Text
                $DirectoryObject.Description = $txtDesc.Text
                $DirectoryObject.office = $txtOffice.Text
                $DirectoryObject.telephoneNumber = $txtPhone.Text
                $DirectoryObject.mail = $txtMail.Text
                $DirectoryObject.wWWHomePage = $txtWeb.Text
                if ($txtStreet) { $DirectoryObject.streetAddress = $txtStreet.Text }
                if ($txtPOBox) { $DirectoryObject.postOfficeBox = $txtPOBox.Text }
                if ($txtCity) { $DirectoryObject.l = $txtCity.Text }
                if ($txtState) { $DirectoryObject.st = $txtState.Text }
                if ($txtZip) { $DirectoryObject.postalCode = $txtZip.Text }
                if ($txtCountry) { $DirectoryObject.co = $txtCountry.Text }
                if ($txtSam) { $DirectoryObject.sAMAccountName = $txtSam.Text }
                if ($txtUpnPrefix -and $cbUpnSuffix) { $DirectoryObject.userPrincipalName = "$($txtUpnPrefix.Text)@$($cbUpnSuffix.SelectedItem)" }
                if ($chkDisabled) { $DirectoryObject.Enabled = (-not $chkDisabled.Checked) }
                if ($chkMustChange) { $DirectoryObject.MustChangePasswordAtNextLogon = $chkMustChange.Checked }
                if ($chkCantChange) { $DirectoryObject.CannotChangePassword = $chkCantChange.Checked }
                if ($chkPassNever) { $DirectoryObject.PasswordNeverExpires = $chkPassNever.Checked }
                if ($chkUnlock -and $chkUnlock.Checked) { $DirectoryObject.LockedOut = $false }
                if ($txtProfPath) { $DirectoryObject.profilePath = $txtProfPath.Text }
                if ($txtScriptPath) { $DirectoryObject.scriptPath = $txtScriptPath.Text }
                if ($rbNetHome) {
                    $DirectoryObject.homeDirectory = $(if ($rbNetHome.Checked) { $txtNetHome.Text } else { $txtLocalHome.Text })
                    $DirectoryObject.homeDrive = $(if ($rbNetHome.Checked) { "$($cbDriveLetter.SelectedItem)" } else { "" })
                }
                if ($txtTelHome) { $DirectoryObject.homePhone = $txtTelHome.Text }
                if ($txtTelPager) { $DirectoryObject.pager = $txtTelPager.Text }
                if ($txtTelMobile) { $DirectoryObject.mobile = $txtTelMobile.Text }
                if ($txtTelFax) { $DirectoryObject.facsimileTelephoneNumber = $txtTelFax.Text }
                if ($txtTelIP) { $DirectoryObject.ipPhone = $txtTelIP.Text }
                if ($txtNotes) { $DirectoryObject.info = $txtNotes.Text }
                if ($txtOrgTitle) { $DirectoryObject.title = $txtOrgTitle.Text }
                if ($txtOrgDept) { $DirectoryObject.department = $txtOrgDept.Text }
                if ($txtOrgComp) { $DirectoryObject.company = $txtOrgComp.Text }
                if ($txtMgrName) { $DirectoryObject.manager = $txtMgrName.Text }
                if ($txtEmpID) { $DirectoryObject.employeeID = $txtEmpID.Text }
                if ($txtEmpNum) { $DirectoryObject.employeeNumber = $txtEmpNum.Text }
                if ($txtEmpType) { $DirectoryObject.employeeType = $txtEmpType.Text }
                if ($txtDivision) { $DirectoryObject.division = $txtDivision.Text }
                if ($txtRdsProf) { $DirectoryObject.msTSProfilePath = $txtRdsProf.Text }
                if ($rbRdsNet) {
                    $DirectoryObject.msTSHomeDirectory = $(if ($rbRdsNet.Checked) { $txtRdsNet.Text } else { $txtRdsLocal.Text })
                    $DirectoryObject.msTSHomeDrive = $(if ($rbRdsNet.Checked) { "$($cbRdsDrive.SelectedItem)" } else { "" })
                }
                if ($chkRdsDeny) { $DirectoryObject.msTSAllowLogon = (-not $chkRdsDeny.Checked) }
                if ($chkStartProg) {
                    $DirectoryObject.msTSInitialProgram = $(if ($chkStartProg.Checked) { $txtProgName.Text } else { "" })
                    $DirectoryObject.msTSWorkDirectory = $(if ($chkStartProg.Checked) { $txtStartIn.Text } else { "" })
                }
                if ($chkRcEnable) {
                    $DirectoryObject.msTSRemoteControl = $(if ($chkRcEnable.Checked) { if ($rbRcInteract.Checked) { 1 } else { 2 } } else { 0 })
                }
                if ($rbDialAllow) {
                    $DirectoryObject.msNPAllowDialin = $(if ($rbDialAllow.Checked) { $true } elseif ($rbDialDeny.Checked) { $false } else { $null })
                }
                if ($chkCallerId) {
                    $DirectoryObject.msNPCallingStationID = $(if ($chkCallerId.Checked) { $txtCallerId.Text } else { "" })
                }
                if ($chkStaticIP) {
                    $DirectoryObject.msRADIUSFramedIPAddress = $(if ($chkStaticIP.Checked) { $txtStaticIP.Text } else { "" })
                }
            } elseif ($isGroup) {
                if ($txtGrpDesc) { $DirectoryObject.Description = $txtGrpDesc.Text }
                if ($txtGrpMail) { $DirectoryObject.mail = $txtGrpMail.Text }
                if ($txtGrpNotes) { $DirectoryObject.info = $txtGrpNotes.Text }
            } elseif ($isComputer) {
                if ($txtCompDesc) { $DirectoryObject.Description = $txtCompDesc.Text }
                if ($txtCompDns) { $DirectoryObject.DNSHostName = $txtCompDns.Text }
                if ($txtCompLoc) { $DirectoryObject.Location = $txtCompLoc.Text }
                if ($txtMgrByName) { $DirectoryObject.manager = $txtMgrByName.Text }
                if ($rbDialAllow) {
                    $DirectoryObject.msNPAllowDialin = $(if ($rbDialAllow.Checked) { $true } elseif ($rbDialDeny.Checked) { $false } else { $null })
                }
                if ($chkCallerId) {
                    $DirectoryObject.msNPCallingStationID = $(if ($chkCallerId.Checked) { $txtCallerId.Text } else { "" })
                }
                if ($chkStaticIP) {
                    $DirectoryObject.msRADIUSFramedIPAddress = $(if ($chkStaticIP.Checked) { $txtStaticIP.Text } else { "" })
                }
            }
            $DirectoryObject.whenChanged = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }

        # Update Attribute Editor view if present
        if ($lvAttr) {
            $fText = if ($txtAttrFilt) { $txtAttrFilt.Text.Trim() } else { "" }
            Update-AttributeListView -ListView $lvAttr -FilterText $fText -OnlyValues $Script:AttrFilterOnlyValues -LdapDefs $allLdapDefs -TargetObject $DirectoryObject
        }
    }

    $btnApply.Add_Click({
        & $SaveAction
        Set-StatusMessage "Applied changes to '$($DirectoryObject.Name)'."
    })

    $dlg.Controls.AddRange(@($tabs, $btnSave, $btnCancel, $btnApply))

    if ($tabs.TabPages.ContainsKey('General')) {
        $tabs.SelectTab('General')
    }

    if ($HeadlessTest) {
        return @{
            Dialog = $dlg
            Tabs = $tabs
            TabCount = $tabs.TabPages.Count
            TabNames = @($tabs.TabPages | ForEach-Object { $_.Text })
            AttributesListView = $lvAttr
            TxtAttrFilt = $txtAttrFilt
            BtnAttrToggle = $btnAttrToggle
            SaveAction = $SaveAction
        }
    }

    $res = $dlg.ShowDialog($Script:MainForm)
    if ($res -eq [System.Windows.Forms.DialogResult]::OK) {
        & $SaveAction
        Set-StatusMessage "Properties updated for '$($DirectoryObject.Name)'."
        Refresh-CurrentContainerView
    }
    $dlg.Dispose()
    return $res
}

# -----------------------------------------------------------------------------
# Event Handlers & Core Workflow
# -----------------------------------------------------------------------------
$Script:CurrentContainerDN = ""
$Script:AllCurrentObjects = [System.Collections.ArrayList]@()
$Script:SelectedObject = $null

function Set-StatusMessage {
    param([string]$Message)
    $lblStatusMessage.Text = $Message
}

function Populate-DirectoryTree {
    $treeView.BeginUpdate()
    $treeView.Nodes.Clear()

    $root = Get-ADRootInformation
    $rootNode = $treeView.Nodes.Add($root.DistinguishedName, $root.Name, "domain", "domain")
    $rootNode.Tag = $root.DistinguishedName

    $containers = Get-ADTreeHierarchy
    $nodeMap = @{ $root.DistinguishedName = $rootNode }

    foreach ($c in $containers) {
        $parent = $nodeMap[$c.ParentDN]
        if (-not $parent) { $parent = $rootNode }
        $icon = if ($c.Type -eq 'ou') { "ou" } else { "container" }
        $newNode = $parent.Nodes.Add($c.DistinguishedName, $c.Name, $icon, $icon)
        $newNode.Tag = $c.DistinguishedName
        $nodeMap[$c.DistinguishedName] = $newNode
    }

    $rootNode.Expand()
    $treeView.EndUpdate()

    if ($treeView.Nodes.Count -gt 0) {
        $treeView.SelectedNode = $rootNode
    }
}

function Load-ContainerObjects {
    param([string]$ContainerDN)

    $Script:CurrentContainerDN = $ContainerDN
    $lblBreadcrumb.Text = "Path: $ContainerDN"

    $objs = Get-ADContainerObjects -ContainerDN $ContainerDN
    $Script:AllCurrentObjects.Clear()
    foreach ($o in $objs) {
        $null = $Script:AllCurrentObjects.Add($o)
    }

    Apply-ObjectFilter
}

function Apply-ObjectFilter {
    $listView.BeginUpdate()
    $listView.Items.Clear()

    $filter = $Script:CurrentTypeFilter
    $query = if ($txtSearch.Text -and $txtSearch.Text -ne "Search directory (Name, SAM, Dept)...") { $txtSearch.Text.Trim().ToLower() } else { "" }

    $filtered = $Script:AllCurrentObjects | Where-Object {
        $matchesType = if ($filter -eq 'All') { $true } else { $_.ObjectClass -eq $filter }
        $matchesSearch = if (-not $query) { $true } else {
            ($_.Name -and $_.Name.ToLower().Contains($query)) -or
            ($_.sAMAccountName -and $_.sAMAccountName.ToLower().Contains($query)) -or
            ($_.department -and $_.department.ToLower().Contains($query)) -or
            ($_.mail -and $_.mail.ToLower().Contains($query)) -or
            ($_.Description -and $_.Description.ToLower().Contains($query))
        }
        $matchesType -and $matchesSearch
    }

    foreach ($item in $filtered) {
        $iconKey = "user_active"
        if ($item.ObjectClass -eq 'user') {
            if (-not $item.Enabled) { $iconKey = "user_disabled" }
            elseif ($item.LockedOut) { $iconKey = "user_locked" }
            else { $iconKey = "user_active" }
        } elseif ($item.ObjectClass -eq 'group') {
            $iconKey = "group"
        } elseif ($item.ObjectClass -eq 'computer') {
            $iconKey = "computer"
        } elseif ($item.ObjectClass -eq 'organizationalUnit') {
            $iconKey = "ou"
        }

        $lvItem = New-Object System.Windows.Forms.ListViewItem($item.Name, $iconKey)
        $lvItem.Tag = $item

        # SubItems: Type, SAM, Status, Description, Department, Modified
        $null = $lvItem.SubItems.Add([string]$item.ObjectClass)
        $null = $lvItem.SubItems.Add([string]$item.sAMAccountName)

        $statusText = "Active"
        if ($item.ObjectClass -eq 'user' -or $item.ObjectClass -eq 'computer') {
            if (-not $item.Enabled) { $statusText = "Disabled" }
            elseif ($item.LockedOut) { $statusText = "Locked Out" }
        }
        $null = $lvItem.SubItems.Add($statusText)
        $null = $lvItem.SubItems.Add([string]$item.Description)
        $null = $lvItem.SubItems.Add([string]$item.department)
        $null = $lvItem.SubItems.Add([string]$item.whenChanged)

        $listView.Items.Add($lvItem) | Out-Null
    }

    $listView.EndUpdate()
    $lblStatusCount.Text = "$($listView.Items.Count) items"

    # Reset inspector drawer
    Clear-InspectorDrawer
}

function Clear-InspectorDrawer {
    $Script:SelectedObject = $null
    $picInspectorAvatar.Image = $null
    $lblInspName.Text = "Select an object to inspect details"
    $lblInspSub.Text = "No object selected."
    $lblInspAttr1.Text = ""
    $lblInspAttr2.Text = ""
    $lblInspAttr3.Text = ""
    $lblInspAttr4.Text = ""

    $btnInspProps.Enabled = $false
    $btnInspMove.Enabled = $false
    $btnInspUnlock.Enabled = $false
    $btnInspToggle.Enabled = $false
    $btnInspPass.Enabled = $false

    if ($btnInspUnlock -is [ADUCK.DarkButton]) {
        $btnInspUnlock.NormalBorderColor = $Script:Theme.BtnBorder
        $btnInspUnlock.NormalForeColor = $Script:Theme.TextPrimary
    }
}

function Update-InspectorDrawer {
    param($item)

    if (-not $item) {
        Clear-InspectorDrawer
        return
    }

    $Script:SelectedObject = $item
    $avatarType = 'ou'
    if ($item.ObjectClass -eq 'user') {
        if (-not $item.Enabled) { $avatarType = 'user_disabled' }
        elseif ($item.LockedOut) { $avatarType = 'user_locked' }
        else { $avatarType = 'user_active' }
    } elseif ($item.ObjectClass -eq 'group') {
        $avatarType = 'group'
    } elseif ($item.ObjectClass -eq 'computer') {
        $avatarType = 'computer'
    }
    $picInspectorAvatar.Image = New-CustomIcon -IconType $avatarType -Size 32

    $lblInspName.Text = $item.Name
    $lblInspSub.Text = "$($item.ObjectClass.ToUpper()) • $($item.sAMAccountName) • $(if ($item.mail) { $item.mail } else { $item.DistinguishedName })"

    $statusBadge = if (-not $item.Enabled) { "[Disabled]" } elseif ($item.LockedOut) { "[Locked Out]" } else { "[Active]" }
    $lblInspAttr1.Text = "Status: $statusBadge"
    $lblInspAttr2.Text = "Title/Dept: $(if ($item.title) { $item.title } else { '-' }) / $(if ($item.department) { $item.department } else { '—' })"
    $lblInspAttr3.Text = "Phone/Office: $(if ($item.telephoneNumber) { $item.telephoneNumber } else { '-' }) / $(if ($item.office) { $item.office } else { '—' })"
    $lblInspAttr4.Text = "Modified: $(if ($item.whenChanged) { $item.whenChanged } else { '-' })"

    $isUser = ($item.ObjectClass -eq 'user')
    $isComp = ($item.ObjectClass -eq 'computer')

    $btnInspProps.Enabled = $true
    $btnInspMove.Enabled = $true
    $btnInspUnlock.Enabled = ($isUser -and $item.LockedOut)
    $btnInspToggle.Enabled = ($isUser -or $isComp)
    $btnInspToggle.Text = if ($item.Enabled) { "Disable" } else { "Enable" }
    $btnInspPass.Enabled = $isUser

    if ($btnInspUnlock -is [ADUCK.DarkButton]) {
        if ($isUser -and $item.LockedOut) {
            $btnInspUnlock.NormalBorderColor = $Script:Theme.Warning
            $btnInspUnlock.NormalForeColor = $Script:Theme.Warning
        } else {
            $btnInspUnlock.NormalBorderColor = $Script:Theme.BtnBorder
            $btnInspUnlock.NormalForeColor = $Script:Theme.TextPrimary
        }
    }
}

function Refresh-CurrentContainerView {
    if ($Script:CurrentContainerDN) {
        Load-ContainerObjects -ContainerDN $Script:CurrentContainerDN
    }
}

# -----------------------------------------------------------------------------
# Event Bindings
# -----------------------------------------------------------------------------
# TreeView Selection
$treeView.Add_AfterSelect({
    param($sender, $e)
    if ($e.Node -and $e.Node.Tag) {
        Load-ContainerObjects -ContainerDN $e.Node.Tag
    }
})

# ListView Selection Changed
$listView.Add_SelectedIndexChanged({
    if ($listView.SelectedItems.Count -gt 0) {
        Update-InspectorDrawer -item $listView.SelectedItems[0].Tag
    } else {
        Clear-InspectorDrawer
    }
})

# Double Click on ListView Item -> Properties
$listView.Add_DoubleClick({
    if ($listView.SelectedItems.Count -gt 0) {
        Show-PropertiesDialog -DirectoryObject $listView.SelectedItems[0].Tag
    }
})

# Search Button & Enter Key
$btnSearch.Add_Click({
    $q = $txtSearch.Text.Trim()
    if ($q -and $q -ne "Search directory (Name, SAM, Dept)...") {
        $results = Search-ADDirectoryObjects -Query $q
        $Script:AllCurrentObjects.Clear()
        foreach ($r in $results) {
            $null = $Script:AllCurrentObjects.Add($r)
        }
        $lblBreadcrumb.Text = "Search Results for '$q'"
        Apply-ObjectFilter
        Set-StatusMessage "Search completed: $($Script:AllCurrentObjects.Count) objects found."
    } else {
        Refresh-CurrentContainerView
    }
})

$txtSearch.Add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        $e.SuppressKeyPress = $true
        $btnSearch.PerformClick()
    }
})

# Refresh All Button
$btnRefreshAll.Add_Click({
    Populate-DirectoryTree
    Refresh-CurrentContainerView
    Set-StatusMessage "Directory refreshed."
})

# Theme System Manager
function Apply-Theme {
    # 1. Update Native DWM Title Bar & Custom ToolStrip Renderer
    [ADUCK.NativeMethods]::ApplyDarkTitleBar($Script:MainForm.Handle, ($Script:Theme.Name -eq 'Dark'))
    $Script:ColorTable.SetPalette($Script:Theme.HeaderBg, $Script:Theme.Surface, $Script:Theme.SurfaceAlt, $Script:Theme.Border, $Script:Theme.Accent)
    $Script:ToolStripRenderer.SetTextColor($Script:Theme.TextPrimary)

    # 2. Main Window
    $Script:MainForm.BackColor = $Script:Theme.Background
    $Script:MainForm.ForeColor = $Script:Theme.TextPrimary

    # 3. Header Panel & Controls
    $pnlHeader.BackColor = $Script:Theme.HeaderBg
    $lblAppTitle.ForeColor = $Script:Theme.TextPrimary
    $lblAppSubtitle.ForeColor = $Script:Theme.TextSecondary

    $root = if ($Script:RootInfo) { $Script:RootInfo } else { Get-ADRootInformation }
    $pnlDomainBadge.BackColor = if ($root.IsDemo) { $Script:Theme.WarningBg } else { $Script:Theme.SuccessBg }
    $lblDomainStatus.ForeColor = if ($root.IsDemo) { $Script:Theme.Warning } else { $Script:Theme.Success }

    # Search Box
    $txtSearch.BackColor = $Script:Theme.InputBg
    if ($txtSearch.Text -eq "Search directory (Name, SAM, Dept)...") {
        $txtSearch.ForeColor = $Script:Theme.TextSecondary
    } else {
        $txtSearch.ForeColor = $Script:Theme.TextPrimary
    }

    # Header Buttons
    if ($btnSearch -is [ADUCK.DarkButton]) {
        $btnSearch.SetPalette(
            $Script:Theme.BtnBg,
            $Script:Theme.TextPrimary,
            $Script:Theme.BtnBorder,
            $Script:Theme.BtnHoverBg,
            $Script:Theme.TextPrimary,
            $Script:Theme.BtnHoverBorder,
            $Script:Theme.BtnDisabledBg,
            $Script:Theme.BtnDisabledFg,
            $Script:Theme.BtnDisabledBorder
        )
    } else {
        $btnSearch.BackColor = $Script:Theme.Surface
        $btnSearch.ForeColor = $Script:Theme.TextPrimary
        $btnSearch.FlatAppearance.BorderColor = $Script:Theme.Border
        $btnSearch.FlatAppearance.MouseOverBackColor = $Script:Theme.SurfaceAlt
    }

    if ($btnRefreshAll -is [ADUCK.DarkButton]) {
        $btnRefreshAll.SetPalette(
            $Script:Theme.BtnBg,
            $Script:Theme.TextPrimary,
            $Script:Theme.BtnBorder,
            $Script:Theme.BtnHoverBg,
            $Script:Theme.TextPrimary,
            $Script:Theme.BtnHoverBorder,
            $Script:Theme.BtnDisabledBg,
            $Script:Theme.BtnDisabledFg,
            $Script:Theme.BtnDisabledBorder
        )
    } else {
        $btnRefreshAll.BackColor = $Script:Theme.Surface
        $btnRefreshAll.ForeColor = $Script:Theme.TextPrimary
        $btnRefreshAll.FlatAppearance.BorderColor = $Script:Theme.Border
        $btnRefreshAll.FlatAppearance.MouseOverBackColor = $Script:Theme.SurfaceAlt
    }

    if ($btnThemeToggle -is [ADUCK.DarkButton]) {
        $btnThemeToggle.SetPalette(
            $Script:Theme.BtnBg,
            $Script:Theme.TextPrimary,
            $Script:Theme.BtnBorder,
            $Script:Theme.BtnHoverBg,
            $Script:Theme.TextPrimary,
            $Script:Theme.BtnHoverBorder,
            $Script:Theme.BtnDisabledBg,
            $Script:Theme.BtnDisabledFg,
            $Script:Theme.BtnDisabledBorder
        )
    } else {
        $btnThemeToggle.BackColor = $Script:Theme.Surface
        $btnThemeToggle.ForeColor = $Script:Theme.TextPrimary
        $btnThemeToggle.FlatAppearance.BorderColor = $Script:Theme.Border
        $btnThemeToggle.FlatAppearance.MouseOverBackColor = $Script:Theme.SurfaceAlt
    }

    if ($btnNewQuick -is [ADUCK.DarkButton]) {
        $btnNewQuick.SetPalette(
            $Script:Theme.AccentDark,
            [System.Drawing.Color]::White,
            $Script:Theme.Accent,
            $Script:Theme.AccentHover,
            [System.Drawing.Color]::White,
            $Script:Theme.Accent,
            $Script:Theme.BtnDisabledBg,
            $Script:Theme.BtnDisabledFg,
            $Script:Theme.BtnDisabledBorder
        )
    } else {
        $btnNewQuick.BackColor = $Script:Theme.AccentDark
        $btnNewQuick.ForeColor = [System.Drawing.Color]::White
        $btnNewQuick.FlatAppearance.BorderColor = $Script:Theme.Accent
        $btnNewQuick.FlatAppearance.MouseOverBackColor = $Script:Theme.AccentHover
    }

    # 4. Splitters
    $splitMain.BackColor = $Script:Theme.Border
    $splitRight.BackColor = $Script:Theme.Border

    # 5. TreeView & Left Pane
    $pnlTreeContainer.BackColor = $Script:Theme.Surface
    $pnlTreeHeader.BackColor = $Script:Theme.SurfaceAlt
    $lblTreeTitle.ForeColor = $Script:Theme.TextSecondary
    $treeView.BackColor = $Script:Theme.Surface
    $treeView.ForeColor = $Script:Theme.TextPrimary
    $treeView.LineColor = $Script:Theme.Border

    # 6. Right Top Bar & Filter Buttons
    $pnlRightContainer.BackColor = $Script:Theme.Background
    $pnlRightTop.BackColor = $Script:Theme.SurfaceAlt
    $lblBreadcrumb.ForeColor = $Script:Theme.TextPrimary

    foreach ($c in $pnlFilters.Controls) {
        if ($c -is [ADUCK.DarkButton]) {
            if ($c.Tag -eq $Script:CurrentTypeFilter) {
                $c.SetPalette(
                    $Script:Theme.AccentDark,
                    [System.Drawing.Color]::White,
                    $Script:Theme.Accent,
                    $Script:Theme.AccentHover,
                    [System.Drawing.Color]::White,
                    $Script:Theme.Accent,
                    $Script:Theme.BtnDisabledBg,
                    $Script:Theme.BtnDisabledFg,
                    $Script:Theme.BtnDisabledBorder
                )
            } else {
                $c.SetPalette(
                    $Script:Theme.BtnBg,
                    $Script:Theme.TextSecondary,
                    $Script:Theme.BtnBorder,
                    $Script:Theme.BtnHoverBg,
                    $Script:Theme.TextPrimary,
                    $Script:Theme.BtnHoverBorder,
                    $Script:Theme.BtnDisabledBg,
                    $Script:Theme.BtnDisabledFg,
                    $Script:Theme.BtnDisabledBorder
                )
            }
        } else {
            if ($c.Tag -eq $Script:CurrentTypeFilter) {
                $c.BackColor = $Script:Theme.AccentDark
                $c.ForeColor = [System.Drawing.Color]::White
                $c.FlatAppearance.BorderColor = $Script:Theme.Accent
                $c.FlatAppearance.MouseOverBackColor = $Script:Theme.AccentHover
            } else {
                $c.BackColor = $Script:Theme.Surface
                $c.ForeColor = $Script:Theme.TextSecondary
                $c.FlatAppearance.BorderColor = $Script:Theme.Border
                $c.FlatAppearance.MouseOverBackColor = $Script:Theme.SurfaceAlt
            }
        }
    }

    # 7. ListView
    $listView.BackColor = $Script:Theme.Surface
    $listView.ForeColor = $Script:Theme.TextPrimary

    # 8. Inspector Drawer
    $pnlInspector.BackColor = $Script:Theme.SurfaceAlt
    $picInspectorAvatar.BackColor = $Script:Theme.ChipBg
    $lblInspName.ForeColor = $Script:Theme.TextPrimary
    $lblInspSub.ForeColor = $Script:Theme.TextSecondary
    $lblInspAttr1.ForeColor = $Script:Theme.TextPrimary
    $lblInspAttr2.ForeColor = $Script:Theme.TextPrimary
    $lblInspAttr3.ForeColor = $Script:Theme.TextPrimary
    $lblInspAttr4.ForeColor = $Script:Theme.TextPrimary

    foreach ($b in $pnlInspActions.Controls) {
        if ($b -is [ADUCK.DarkButton]) {
            $hBg = $Script:Theme.BtnHoverBg
            $hBorder = $Script:Theme.BtnHoverBorder
            if ($b.Tag -eq 'unlock') {
                $hBg = $Script:Theme.WarningBg
                $hBorder = $Script:Theme.Warning
            } elseif ($b.Tag -eq 'pass') {
                $hBg = $Script:Theme.AccentDark
                $hBorder = $Script:Theme.Accent
            }

            $b.SetPalette(
                $Script:Theme.BtnBg,
                $Script:Theme.TextPrimary,
                $Script:Theme.BtnBorder,
                $hBg,
                $Script:Theme.TextPrimary,
                $hBorder,
                $Script:Theme.BtnDisabledBg,
                $Script:Theme.BtnDisabledFg,
                $Script:Theme.BtnDisabledBorder
            )
        } else {
            $b.BackColor = $Script:Theme.Surface
            $b.ForeColor = $Script:Theme.TextPrimary
            $b.FlatAppearance.BorderColor = $Script:Theme.Border
            $b.FlatAppearance.MouseOverBackColor = $Script:Theme.SurfaceAlt
        }
    }

    # 9. StatusStrip
    $statusStrip.BackColor = $Script:Theme.HeaderBg
    $statusStrip.ForeColor = $Script:Theme.TextSecondary
    foreach ($item in $statusStrip.Items) {
        $item.ForeColor = $Script:Theme.TextSecondary
    }

    # 10. Context Menus
    $treeContextMenu.BackColor = $Script:Theme.Surface
    $treeContextMenu.ForeColor = $Script:Theme.TextPrimary
    $itemContextMenu.BackColor = $Script:Theme.Surface
    $itemContextMenu.ForeColor = $Script:Theme.TextPrimary
    $newQuickMenu.BackColor = $Script:Theme.Surface
    $newQuickMenu.ForeColor = $Script:Theme.TextPrimary

    # 11. Refresh Inspector Drawer if object is selected
    if ($Script:SelectedObject) {
        Update-InspectorDrawer -item $Script:SelectedObject
    }

    $Script:MainForm.Refresh()
}

# Theme Toggle
$btnThemeToggle.Add_Click({
    if ($Script:Theme.Name -eq 'Dark') {
        $Script:Theme = $Script:ThemeLight
    } else {
        $Script:Theme = $Script:ThemeDark
    }
    Apply-Theme
    Set-StatusMessage "Switched to $($Script:Theme.Name) theme."
})

# Context Menu & Action Button Handlers
$btnInspPass.Add_Click({
    if ($Script:SelectedObject) { Show-ResetPasswordDialog -UserObject $Script:SelectedObject }
})
$mnuItemPass.Add_Click({
    if ($listView.SelectedItems.Count -gt 0) { Show-ResetPasswordDialog -UserObject $listView.SelectedItems[0].Tag }
})

$btnInspToggle.Add_Click({
    if ($Script:SelectedObject) {
        $newState = (-not $Script:SelectedObject.Enabled)
        Set-ADObjectState -DistinguishedName $Script:SelectedObject.DistinguishedName -Enable $newState
        Set-StatusMessage "Account '$($Script:SelectedObject.Name)' $(if ($newState) { 'enabled' } else { 'disabled' })."
        Refresh-CurrentContainerView
    }
})
$mnuItemToggle.Add_Click({
    if ($listView.SelectedItems.Count -gt 0) {
        $obj = $listView.SelectedItems[0].Tag
        $newState = (-not $obj.Enabled)
        Set-ADObjectState -DistinguishedName $obj.DistinguishedName -Enable $newState
        Set-StatusMessage "Account '$($obj.Name)' $(if ($newState) { 'enabled' } else { 'disabled' })."
        Refresh-CurrentContainerView
    }
})

$btnInspUnlock.Add_Click({
    if ($Script:SelectedObject) {
        Invoke-ADUnlockAccount -DistinguishedName $Script:SelectedObject.DistinguishedName
        Set-StatusMessage "Account '$($Script:SelectedObject.Name)' unlocked."
        Refresh-CurrentContainerView
    }
})
$mnuItemUnlock.Add_Click({
    if ($listView.SelectedItems.Count -gt 0) {
        $obj = $listView.SelectedItems[0].Tag
        Invoke-ADUnlockAccount -DistinguishedName $obj.DistinguishedName
        Set-StatusMessage "Account '$($obj.Name)' unlocked."
        Refresh-CurrentContainerView
    }
})

$btnInspMove.Add_Click({
    if ($Script:SelectedObject) { Show-MoveObjectDialog -DirectoryObject $Script:SelectedObject }
})
$mnuItemMove.Add_Click({
    if ($listView.SelectedItems.Count -gt 0) { Show-MoveObjectDialog -DirectoryObject $listView.SelectedItems[0].Tag }
})

$btnInspProps.Add_Click({
    if ($Script:SelectedObject) { Show-PropertiesDialog -DirectoryObject $Script:SelectedObject }
})
$mnuItemProps.Add_Click({
    if ($listView.SelectedItems.Count -gt 0) { Show-PropertiesDialog -DirectoryObject $listView.SelectedItems[0].Tag }
})

# Copy DN
$mnuItemCopyDN.Add_Click({
    if ($listView.SelectedItems.Count -gt 0) {
        [System.Windows.Forms.Clipboard]::SetText($listView.SelectedItems[0].Tag.DistinguishedName)
        Set-StatusMessage "Distinguished Name copied to clipboard."
    }
})
$mnuTreeCopyDN.Add_Click({
    if ($treeView.SelectedNode) {
        [System.Windows.Forms.Clipboard]::SetText($treeView.SelectedNode.Tag)
        Set-StatusMessage "Distinguished Name copied to clipboard."
    }
})

# Delete Object
$mnuItemDel.Add_Click({
    if ($listView.SelectedItems.Count -gt 0) {
        $obj = $listView.SelectedItems[0].Tag
        $confirm = [System.Windows.Forms.MessageBox]::Show("Are you sure you want to delete '$($obj.Name)'?", "Confirm Delete", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
        if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
            Remove-ADDirectoryObject -DistinguishedName $obj.DistinguishedName
            Set-StatusMessage "Deleted '$($obj.Name)'."
            Refresh-CurrentContainerView
        }
    }
})

# TreeView Right-Click node selection
$treeView.Add_NodeMouseClick({
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
        $treeView.SelectedNode = $e.Node
    }
})

# TreeView Context Menu Dynamic Specialization (Domain Root vs OU vs Container)
$treeContextMenu.Add_Opening({
    param($sender, $e)
    $selected = $treeView.SelectedNode
    if (-not $selected) { return }

    $isDomainRoot = ($selected.Parent -eq $null -or $selected.Tag -eq $Script:RootInfo.DistinguishedName)
    $isOU = ($selected.ImageKey -eq 'ou' -or ($selected.Tag -like "OU=*"))

    $mnuTreeDelegate.Visible  = ($isDomainRoot -or $isOU)
    $mnuTreeChangeDom.Visible = $isDomainRoot
    $mnuTreeChangeDC.Visible  = $isDomainRoot
    $mnuTreeRaiseDFL.Visible  = $isDomainRoot
    $mnuTreeSepDomain.Visible = ($isDomainRoot -or $isOU)

    $mnuTreeNewOU.Visible = ($isDomainRoot -or $isOU)
})

# Domain Context Menu Action Handlers
$mnuTreeDelegate.Add_Click({
    $targetDN = if ($treeView.SelectedNode) { $treeView.SelectedNode.Tag } else { $Script:RootInfo.DistinguishedName }
    Show-DelegateControlDialog -TargetContainerDN $targetDN
})
$mnuTreeChangeDom.Add_Click({ Show-ChangeDomainDialog })
$mnuTreeChangeDC.Add_Click({ Show-ChangeDomainControllerDialog })
$mnuTreeRaiseDFL.Add_Click({ Show-RaiseDomainFunctionalLevelDialog })

# New Object Menu Handlers
$mnuTreeNewUser.Add_Click({ Show-NewUserDialog -TargetContainerDN $treeView.SelectedNode.Tag })
$mnuQNewUser.Add_Click({ Show-NewUserDialog -TargetContainerDN $Script:CurrentContainerDN })

$mnuTreeNewGroup.Add_Click({ Show-NewGroupDialog -TargetContainerDN $treeView.SelectedNode.Tag })
$mnuQNewGrp.Add_Click({ Show-NewGroupDialog -TargetContainerDN $Script:CurrentContainerDN })

$mnuTreeNewComp.Add_Click({ Show-NewComputerDialog -TargetContainerDN $treeView.SelectedNode.Tag })
$mnuQNewComp.Add_Click({ Show-NewComputerDialog -TargetContainerDN $Script:CurrentContainerDN })

$mnuTreeNewOU.Add_Click({ Show-NewOUDialog -TargetContainerDN $treeView.SelectedNode.Tag })
$mnuQNewOU.Add_Click({ Show-NewOUDialog -TargetContainerDN $Script:CurrentContainerDN })

$mnuTreeRefresh.Add_Click({ Refresh-CurrentContainerView })

# Initialize and Show Application
Apply-Theme
Populate-DirectoryTree
Clear-InspectorDrawer

$Script:MainForm.Add_Shown({
    try {
        $splitMain.SplitterDistance = 280
        if ($splitRight.Height -gt 250) {
            $splitRight.SplitterDistance = $splitRight.Height - 140
        }
    } catch {}
})

[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::Run($Script:MainForm)
