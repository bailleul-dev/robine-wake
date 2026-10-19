//// Entry point: the component `index.js` registers with Expo.

import redraw.{type Element}
import robine/app

pub fn root(props: Nil) -> Element {
  app.app(props)
}
