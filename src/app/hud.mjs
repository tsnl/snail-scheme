// The HUD: four corner panels of labels, buttons and meters. A panel is
// rebuilt only when its description changes.

const anchors = ['top-left', 'top-right', 'bottom-left', 'bottom-right'];
const LABEL = 0, BUTTON = 1, SELECTED = 2, METER = 3;

function widgetElement(widget, press) {
  if (widget.kind === BUTTON || widget.kind === SELECTED) {
    const button = document.createElement('button');
    button.textContent = widget.text;
    button.className = widget.kind === SELECTED ? 'selected' : '';
    button.addEventListener('click', () => press(widget.action));
    return button;
  }
  const element = document.createElement('div');
  element.className = widget.kind === METER ? 'meter' : 'label';
  element.textContent = widget.text;
  if (widget.kind === METER) element.style.setProperty('--fill', `${Math.round(widget.value * 100)}%`);
  return element;
}

export function createHud(overlay, press) {
  const panels = anchors.map(anchor => {
    const element = document.createElement('div');
    element.className = `panel ${anchor}`;
    overlay.append(element);
    return {element, description: ''};
  });
  return {
    update(descriptions) {
      panels.forEach((panel, index) => {
        const widgets = descriptions.filter(d => d.anchor === index).flatMap(d => d.widgets);
        const description = JSON.stringify(widgets);
        if (description === panel.description) return;
        panel.description = description;
        panel.element.replaceChildren(...widgets.map(widget => widgetElement(widget, press)));
      });
    },
  };
}
