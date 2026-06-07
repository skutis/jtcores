#!/usr/bin/env python3
import argparse
import os
import sys

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import Gdk, GdkPixbuf, GLib, Gtk


class ImageWatcher:
    def __init__(self, path, interval_ms, zoom, hbase, vbase):
        self.path = path
        self.directory = os.path.dirname(path) or "."
        self.files = []
        self.index = 0
        self.interval_ms = interval_ms
        self.zoom = zoom
        self.hbase = hbase
        self.vbase = vbase
        self.mtime = None
        self.base_pixbuf = None
        self.drag_button = None
        self.drag_x = 0.0
        self.drag_y = 0.0
        self.drag_h = 0.0
        self.drag_v = 0.0
        self.maximized = False
        self.coord_text = "x=- y=-"
        self.coremod = self.read_coremod()
        self.scaled_width = 0
        self.scaled_height = 0

        self.window = Gtk.Window(title="watch_image")
        self.window.set_default_size(900, 700)
        self.window.add_events(Gdk.EventMask.SCROLL_MASK | Gdk.EventMask.SMOOTH_SCROLL_MASK)
        self.window.connect("destroy", Gtk.main_quit)
        self.window.connect("key-press-event", self.on_key_press)
        self.window.connect("scroll-event", self.on_scroll)
        self.window.connect("window-state-event", self.on_window_state)

        self.header = Gtk.HeaderBar()
        self.header.set_show_close_button(True)
        self.header.set_title("watch_image")

        self.min_button = Gtk.Button(label="_")
        self.min_button.set_tooltip_text("Minimize")
        self.min_button.connect("clicked", self.on_minimize)

        self.max_button = Gtk.Button(label="[]")
        self.max_button.set_tooltip_text("Maximize")
        self.max_button.connect("clicked", self.on_maximize)

        self.header.pack_end(self.max_button)
        self.header.pack_end(self.min_button)
        self.window.set_titlebar(self.header)

        self.image = Gtk.Image()
        self.event_box = Gtk.EventBox()
        self.event_box.add_events(
            Gdk.EventMask.SCROLL_MASK
            | Gdk.EventMask.SMOOTH_SCROLL_MASK
            | Gdk.EventMask.BUTTON_PRESS_MASK
            | Gdk.EventMask.BUTTON_RELEASE_MASK
            | Gdk.EventMask.POINTER_MOTION_MASK
        )
        self.event_box.connect("scroll-event", self.on_scroll)
        self.event_box.connect("button-press-event", self.on_button_press)
        self.event_box.connect("button-release-event", self.on_button_release)
        self.event_box.connect("motion-notify-event", self.on_motion)
        self.event_box.add(self.image)

        self.scrolled = Gtk.ScrolledWindow()
        self.scrolled.add_events(Gdk.EventMask.SCROLL_MASK | Gdk.EventMask.SMOOTH_SCROLL_MASK)
        self.scrolled.connect("scroll-event", self.on_scroll)
        self.viewport = Gtk.Viewport()
        self.viewport.add(self.event_box)
        self.scrolled.add(self.viewport)
        self.window.add(self.scrolled)
        self.window.show_all()

        self.refresh_file_list()
        self.reload(force=True)
        GLib.timeout_add(self.interval_ms, self.poll)

    def poll(self):
        self.refresh_file_list()
        self.reload(force=False)
        return True

    def refresh_file_list(self):
        try:
            names = os.listdir(self.directory)
        except OSError:
            return

        files = [
            os.path.join(self.directory, name)
            for name in names
            if name.lower().endswith((".jpg", ".jpeg", ".png"))
        ]
        files.sort()
        if not files:
            return

        current = os.path.abspath(self.path)
        self.files = files
        for i, name in enumerate(files):
            if os.path.abspath(name) == current:
                self.index = i
                break
        else:
            self.index = min(self.index, len(files) - 1)
            self.path = files[self.index]
            self.mtime = None

    def stat_mtime(self):
        try:
            st = os.stat(self.path)
            return (st.st_mtime_ns, st.st_size)
        except FileNotFoundError:
            return None

    def read_coremod(self):
        try:
            with open("core.mod", "rb") as f:
                data = f.read(1)
        except OSError:
            return 0
        return data[0] if data else 0

    def reload(self, force):
        mtime = self.stat_mtime()
        if mtime is None:
            return
        if not force and mtime == self.mtime:
            return
        try:
            pixbuf = GdkPixbuf.Pixbuf.new_from_file(self.path)
        except GLib.Error:
            return

        self.mtime = mtime
        self.base_pixbuf = pixbuf
        self.update_image()

    def update_title(self):
        if self.base_pixbuf is None:
            return

        width = max(1, int(round(self.base_pixbuf.get_width() * self.zoom)))
        height = max(1, int(round(self.base_pixbuf.get_height() * self.zoom)))
        title = (
            f"{os.path.basename(self.path)}  {self.index + 1}/{len(self.files)}  "
            f"zoom={self.zoom:.2f}x  {width}x{height}  {self.coord_text}"
        )
        self.window.set_title(title)
        self.header.set_title(title)

    def update_coords(self, x, y):
        if self.base_pixbuf is None:
            return

        alloc = self.image.get_allocation()
        px = x - alloc.x
        py = y - alloc.y
        if self.scaled_width and self.scaled_height:
            px -= max(0, (alloc.width - self.scaled_width) / 2)
            py -= max(0, (alloc.height - self.scaled_height) / 2)

        img_x = int(px / self.zoom)
        img_y = int(py / self.zoom)
        if (
            0 <= img_x < self.base_pixbuf.get_width()
            and 0 <= img_y < self.base_pixbuf.get_height()
        ):
            raw_x, raw_y = self.raw_coords(img_x, img_y)
            hpos = (raw_x + self.hbase) % 384
            vpos = (raw_y + self.vbase) % 264
            self.coord_text = (
                f"img x={img_x} y={img_y}  raw x={raw_x} y={raw_y}  "
                f"hpos={hpos} vpos={vpos}"
            )
        else:
            self.coord_text = "x=- y=-"
        self.update_title()

    def raw_coords(self, img_x, img_y):
        if not (self.coremod & 1):
            return img_x, img_y

        raw_w = self.base_pixbuf.get_height()
        raw_h = self.base_pixbuf.get_width()
        ccw = bool(self.coremod & 4)
        if ccw:
            return img_y, raw_h - 1 - img_x
        return img_y, raw_h - 1 - img_x

    def update_image(self, scroll_to=None):
        if self.base_pixbuf is None:
            return

        hadj = self.scrolled.get_hadjustment()
        vadj = self.scrolled.get_vadjustment()
        old_x, old_y = scroll_to if scroll_to is not None else (hadj.get_value(), vadj.get_value())

        width = max(1, int(round(self.base_pixbuf.get_width() * self.zoom)))
        height = max(1, int(round(self.base_pixbuf.get_height() * self.zoom)))
        self.scaled_width = width
        self.scaled_height = height
        interp = GdkPixbuf.InterpType.NEAREST
        scaled = self.base_pixbuf.scale_simple(width, height, interp)
        self.image.set_from_pixbuf(scaled)

        self.update_title()

        GLib.idle_add(self.restore_scroll, old_x, old_y)

    def restore_scroll(self, x, y):
        hadj = self.scrolled.get_hadjustment()
        vadj = self.scrolled.get_vadjustment()
        self.set_scroll(hadj, x)
        self.set_scroll(vadj, y)
        return False

    def set_scroll(self, adjustment, value):
        upper = max(0, adjustment.get_upper() - adjustment.get_page_size())
        adjustment.set_value(max(0, min(value, upper)))

    def set_zoom(self, zoom):
        self.zoom = max(0.25, min(32.0, zoom))
        self.update_image()

    def set_zoom_at(self, zoom, x, y):
        old_zoom = self.zoom
        new_zoom = max(0.25, min(32.0, zoom))
        if new_zoom == old_zoom:
            return

        hadj = self.scrolled.get_hadjustment()
        vadj = self.scrolled.get_vadjustment()
        img_x = (hadj.get_value() + x) / old_zoom
        img_y = (vadj.get_value() + y) / old_zoom

        self.zoom = new_zoom
        self.update_image((img_x * new_zoom - x, img_y * new_zoom - y))

    def step_file(self, delta):
        self.refresh_file_list()
        if not self.files:
            return
        self.index = (self.index + delta) % len(self.files)
        self.path = self.files[self.index]
        self.mtime = None
        self.reload(force=True)

    def on_key_press(self, _window, event):
        key = Gdk.keyval_name(event.keyval)
        if key in ("q", "Q", "Escape"):
            Gtk.main_quit()
        elif key in ("Left", "KP_Left"):
            self.step_file(-1)
        elif key in ("Right", "KP_Right"):
            self.step_file(1)
        elif key in ("plus", "KP_Add", "equal"):
            self.set_zoom(self.zoom * 1.25)
        elif key in ("minus", "KP_Subtract", "underscore"):
            self.set_zoom(self.zoom / 1.25)
        elif key in ("0", "KP_0"):
            self.set_zoom(1.0)
        elif key in ("r", "R"):
            self.reload(force=True)

    def on_scroll(self, _widget, event):
        if event.direction == Gdk.ScrollDirection.UP:
            factor = 1.25
        elif event.direction == Gdk.ScrollDirection.DOWN:
            factor = 1 / 1.25
        elif event.direction == Gdk.ScrollDirection.SMOOTH:
            deltas = event.get_scroll_deltas()
            if len(deltas) == 3:
                _ok, _dx, dy = deltas
            else:
                _dx, dy = deltas
            factor = 1.25 ** (-dy)
        else:
            return False

        self.set_zoom_at(self.zoom * factor, event.x, event.y)
        return True

    def on_button_press(self, widget, event):
        if event.button not in (2, 3):
            return False

        self.drag_button = event.button
        self.drag_x = event.x_root
        self.drag_y = event.y_root
        self.drag_h = self.scrolled.get_hadjustment().get_value()
        self.drag_v = self.scrolled.get_vadjustment().get_value()
        widget.grab_focus()
        return True

    def on_button_release(self, _widget, event):
        if event.button == self.drag_button:
            self.drag_button = None
            return True
        return False

    def on_motion(self, _widget, event):
        self.update_coords(event.x, event.y)
        if self.drag_button is None:
            return False

        hadj = self.scrolled.get_hadjustment()
        vadj = self.scrolled.get_vadjustment()
        self.set_scroll(hadj, self.drag_h - (event.x_root - self.drag_x))
        self.set_scroll(vadj, self.drag_v - (event.y_root - self.drag_y))
        return True

    def on_minimize(self, _button):
        self.window.iconify()

    def on_maximize(self, _button):
        if self.maximized:
            self.window.unmaximize()
        else:
            self.window.maximize()

    def on_window_state(self, _window, event):
        self.maximized = bool(event.new_window_state & Gdk.WindowState.MAXIMIZED)
        self.max_button.set_label("<>" if self.maximized else "[]")
        self.max_button.set_tooltip_text("Restore" if self.maximized else "Maximize")
        return False


def main():
    parser = argparse.ArgumentParser(
        description="Auto-reloading image viewer that preserves zoom and pan."
    )
    parser.add_argument(
        "path",
        nargs="*",
        default="frames/frame_00004.png",
        help="image file(s) to watch, default: frames/frame_00004.png",
    )
    parser.add_argument("--interval", type=float, default=0.25, help="poll interval in seconds")
    parser.add_argument("--zoom", type=float, default=3.0, help="initial zoom")
    parser.add_argument("--hbase", type=int, default=0, help="raw active x to hpos offset")
    parser.add_argument("--vbase", type=int, default=16, help="raw active y to vpos offset")
    args = parser.parse_args()

    path = args.path[0] if args.path else "frames/frame_00004.png"
    ImageWatcher(path, max(50, int(args.interval * 1000)), args.zoom, args.hbase, args.vbase)
    Gtk.main()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
