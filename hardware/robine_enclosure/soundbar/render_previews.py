"""Render PNG previews of the generated sound bar with the FreeCAD GUI.

    /Applications/FreeCAD.app/Contents/MacOS/FreeCAD render_previews.py

Run ``design_soundbar.py`` first; the window closes when rendering is done.
"""

import os
from pathlib import Path

import FreeCAD as App
import FreeCADGui as Gui


def out_dir() -> Path:
    if os.environ.get("ROBINE_OUT"):
        return Path(os.environ["ROBINE_OUT"])
    here = Path(__file__).resolve().parent if "__file__" in globals() else Path.cwd()
    return here / "generated"


def render() -> None:
    target = out_dir()
    doc = App.openDocument(str(target / "robine-soundbar.FCStd"))
    Gui.ActiveDocument = Gui.getDocument(doc.Name)
    view = Gui.ActiveDocument.ActiveView
    for obj in doc.Objects:
        if hasattr(obj, "DesignColor"):
            obj.ViewObject.ShapeColor = obj.DesignColor[:3]
    hidden_when_open = ["top", "front", "end_left"]

    from pivy import coin

    centre = coin.SbVec3f(450, 60, 55)

    def shot(name, direction, hide=(), zoom=1.0):
        for obj in doc.Objects:
            if obj.TypeId == "Part::Feature":
                obj.ViewObject.Visibility = obj.Name not in hide
        cam = view.getCameraNode()
        cam.position.setValue(centre + coin.SbVec3f(*direction))
        cam.pointAt(centre, coin.SbVec3f(0, 0, 1))
        view.fitAll()
        cam.scaleHeight(zoom)
        view.saveImage(str(target / f"preview-{name}.png"), 1800, 1000, "White")

    # Seen from the pillow, under the bar: baffle, drivers and hatch.
    shot("below", (-350, 900, -650), zoom=0.62)
    # Room side, from above.
    shot("iso", (-500, 900, 650), zoom=0.62)
    # Top, front and one end removed to show the bay and chambers.
    shot("open", (-450, 800, 750), ["top", "front", "end_left"], zoom=0.62)
    # End view without the left cheek: tilted profile and French cleat.
    shot("side", (-1500, 0, 0), ["end_left"], zoom=0.2)
    App.closeDocument(doc.Name)


render()
os._exit(0)
