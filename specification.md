## Life Simulator

This application focuses on implementing Conway's Life simulation rules.

## Functionality

**Run life simulation** - This iterates through generations and renders the next generation of life based on conway's life rules:

- Any live cell with fewer than two live neighbors dies (underpopulation).
- Any live cell with two or three live neighbors lives on to the next generation.
- Any live cell with more than three live neighbors dies (overpopulation).
- Any dead cell with exactly three live neighbors becomes a live cell (reproduction).
- Neighbors are the eight adjacent cells (horizontal, vertical, diagonal).

**Edit life grid** - The ability for a use to activate life cells by clicking on the grid. The grid is an infinite grid, so the user can drag the grid and place life cells where they would like.

## Design
The user interface for humans must have a design system that supports themes this includes:

### First-Run Experience
- When the app launches with an empty universe, guide the user through placing initial life: display a lightweight overlay that highlights tap/click gestures and offers quick actions to drop common starter patterns (e.g., Glider, Blinker, Block).
- Provide a dismissible inline hint near the grid that explains how to toggle cells, pan, and zoom; ensure it only reappears when the grid is empty to avoid clutter.
- Seed the analytics header with explanatory copy until the simulation has produced at least one generation so the top area is not visually barren on first run.
- Offer a “Custom” option during first run that simply closes the overlay and highlights that users can paint cells directly on the grid.

### UI Layout
- **Header analytics bar** sits at the top with room for graphs and key simulation metrics; it remains visible while the grid updates.
- **Infinite grid canvas** fills the remaining vertical space between header and control bar; initial viewport is centered on coordinate (0,0) and must support panning/zooming for an effectively unbounded world.
- **Control bar** anchors to the bottom, offering media-style playback controls (play, pause, step, reset) plus game-specific actions; sized smaller than the header so the grid visually dominates.
- Layout adapts to iPhone/iPad/Mac, keeping the header + controls at fixed heights while the grid flexes.
- Live cells render as sharp, square tiles (no rounded corners) with a configurable fill color sourced from Settings.
- The analytics header tracks current population, max live cells, min live cells, and shows a compact sparkline of population over recent generations.
- The grid supports direct editing via an edit mode: when enabled, users can stamp pre-defined patterns or toggle individual cells; pointer hover highlights the target square with a border using the configured life color.
- Rendering, hover outlines, and hit-testing must share the same coordinate transform so visual cells always sit exactly inside grid lines—no offsets between the drawn square, grid highlight, and the cell that toggles.

### Edit Toolbar
- Provide a left-aligned toolbar (visible only in edit mode) with at least ten well-known Conway patterns (e.g., Glider, Lightweight spaceship, Pulsar, Gosper glider gun, Block, Blinker, Toad, Beacon, Loaf, Boat) that users can stamp onto the grid. The toolbar should feel integrated with the window chrome and push the grid content to the right when visible.
- Selecting a pattern enters stamp mode: the pattern preview follows the cursor with a translucent overlay matching the life color until placement. Clicking commits the pattern; pressing Escape cancels without placement.
- Include an edit-mode toggle in the control bar; the application launches with edit mode on and the toolbar visible, replacing the old first-run overlay.
- Maintain an undo/redo history of at least 50 actions (stamps, toggles, clears). Support Command+Z for undo and Command+Shift+Z for redo. Playing the simulation clears the action history.

## Auto-zoom
As life iterates through generations, it is important to see where all of the life is, so the application should auto-zoom the grid each generation to ensure that the life is visible. We should make auto-zoom smooth by adding a buffer zone around the visible grid area. So keeping 20% of the visible rows and columns on the outside of the grid as the buffer. If there are 10x10 grid this then the first two rows, first two columns of squares and the last two rows and last two columns of squares are the buffer zone for zooming.
* auto-zoom out - as life grows we want to auto-zoom out
* auto-zoom in - if life is shrinking we want to auto-zoom in
- Avoid disrupting the user’s framing when the buffered live area already fits on screen; only adjust zoom/pan when required to keep the population visible or when explicitly forced.
- While the simulation is playing with auto-zoom enabled, automatically zoom out when live cells would extend beyond the buffered view so the entire population remains visible; zoom back in when the bounding box shrinks.

## Auto-stop
When the generations come to an end the life simulator should stop "playing" the simulation as the simulation is complete.

## Zoom controls
- Provide explicit zoom in/out buttons in the bottom control bar with smooth animated scaling of the grid.
- Support pinch-to-zoom gestures on trackpads and touch screens; scroll-wheel pinch should map to the same zoom scale.
- Zoom can scale far out; when the zoom factor represents a 2×, 3×, or 4× zoom-out, draw 2×2, 3×3, or 4×4 blocks respectively so detail stays legible. The furthest zoom should show a 4×4 block occupying the same screen size as a single cell at 1×.
- Grid lines snap to the same aggregation levels as the cells: at 2× zoom the lattice outlines 2×2 squares, at 3× zoom it outlines 3×3 squares, etc. The hover highlight still describes a single life cell so the user can toggle individual cells regardless of zoom.

## Settings
- Present a settings popup accessible from the control bar that surfaces simulation and display options without leaving the grid.
- Allow users to adjust generation speed with a slider or segmented control (e.g., slow/normal/fast) that updates playback in real time.
- Include toggles for auto-zoom (default on) and auto-stop (default on), with concise explanations of their behavior. When auto-zoom is enabled, offer a mode selector:
  - `Fit` (default): zoom both in and out so the buffered live area stays visible.
  - `Out`: only zoom out (never zoom in automatically) ensuring existing framing is preserved while guaranteeing visibility.
- Provide a color picker for life cells (solid color, no opacity slider) so users can customize the grid appearance.
- Extend theming with color pickers for the grid background, grid lines, and the center axes so users can tailor the board to their preference.
- Persist chosen settings so subsequent launches respect user preferences while still offering a quick “Reset to defaults” action.
- The modal should feel compact and intentional: maintain 24pt horizontal padding, 20–24pt vertical spacing between sections, and constrain the content width so controls do not stretch edge-to-edge.
- Group related controls under clear section headers and ensure buttons align with their section content rather than the full sheet width. 
