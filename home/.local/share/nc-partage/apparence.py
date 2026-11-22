"""Composants GTK aux couleurs des cartes Cloud de l'île."""
import json
from pathlib import Path
import re
from gi.repository import Gdk, Gtk


def theme(config):
    palette = dict(fond="#000000", texte="#ffffff", texteSec="#98989d", carte="#1c1c1e",
                   gris2="#2c2c2e", gris3="#3a3a3c", accent="#0a84ff", surAccent="#ffffff")
    try:
        settings = (config/"reglages.conf").read_text() if (config/"reglages.conf").exists() else ""
        if not re.search(r'^ILE_STYLE=["\']?noir', settings, re.M):
            custom = json.loads((config/"palette-ile.json").read_text())
            palette.update({k: v for k, v in custom.items() if k in palette and isinstance(v, str)
                            and re.fullmatch(r"#[0-9a-fA-F]{6}", v)})
    except (OSError, ValueError):
        pass
    css = Gtk.CssProvider()
    css.load_from_data(("""
    .partage { background-color: %(fond)s; color: %(texte)s; }
    .partage label { color: %(texte)s; }
    .partage .carte { background: %(carte)s; border: 1px solid %(gris3)s; border-radius: 16px; padding: 15px; }
    .partage .titre { font-size: 23px; font-weight: bold; }
    .partage .section { font-size: 16px; font-weight: bold; }
    .partage .detail { color: %(texteSec)s; font-size: 13px; }
    .partage .symbole { color: %(accent)s; }
    .partage button, .partage entry { background: %(gris2)s; color: %(texte)s;
        border: 1px solid %(gris3)s; border-radius: 12px; box-shadow: none; text-shadow: none; }
    .partage button:hover, .partage button:focus, .partage entry:focus { border-color: %(accent)s; }
    .partage button:disabled { opacity: 0.48; }
    .partage .principal { background: %(accent)s; color: %(surAccent)s; font-weight: bold; }
    .partage .principal label { color: %(surAccent)s; }
    """ % palette).encode())
    Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)


def label(text, style="detail", selectable=False):
    widget = Gtk.Label(label=text, xalign=0, wrap=True, selectable=selectable)
    widget.set_max_width_chars(70)
    widget.get_style_context().add_class(style)
    return widget


def card(parent, title, icon):
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=9)
    box.get_style_context().add_class("carte")
    parent.add(box)
    header = Gtk.Box(spacing=8)
    glyph = Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.BUTTON)
    glyph.get_style_context().add_class("symbole")
    header.add(glyph)
    header.add(label(title, "section"))
    box.add(header)
    return box
