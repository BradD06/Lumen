import Foundation

/// Скрипт, который читалка встраивает в каждую главу: сообщает о выделении и прокрутке,
/// красит выделения и прокручивает к ним. Место выделения запоминается текстом и числом
/// символов до него, поэтому находится снова, даже если поменяли шрифт или ширину окна.
enum ReaderScript {
    static let handlerName = "lumen"

    static let source = #"""
    (function () {
      if (window.lumen) { return; }
      const post = (message) => {
        try { window.webkit.messageHandlers.lumen.postMessage(message); } catch (e) {}
      };

      const style = document.createElement('style');
      style.id = 'lumen-style';
      (document.head || document.documentElement).appendChild(style);

      function textNodes() {
        const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
        const nodes = [];
        let node;
        while ((node = walker.nextNode())) { nodes.push(node); }
        return nodes;
      }

      function offsetOf(container, offset) {
        const range = document.createRange();
        range.setStart(document.body, 0);
        range.setEnd(container, offset);
        return range.toString().length;
      }

      function labelOf(node) {
        let element = node.nodeType === 1 ? node : node.parentElement;
        while (element) {
          if (element.dataset && element.dataset.lumenLabel) { return element.dataset.lumenLabel; }
          element = element.parentElement;
        }
        return null;
      }

      function progression() {
        const max = document.documentElement.scrollHeight - window.innerHeight;
        return max > 0 ? Math.min(Math.max(window.scrollY / max, 0), 1) : 0;
      }

      // Из нескольких одинаковых фрагментов берётся ближайший к запомненному месту.
      function locate(text, approx) {
        if (!text) { return null; }
        const nodes = textNodes();
        const starts = [];
        let full = '';
        for (const node of nodes) { starts.push(full.length); full += node.data; }
        let best = -1;
        let index = full.indexOf(text);
        while (index !== -1) {
          if (best === -1 || Math.abs(index - approx) < Math.abs(best - approx)) { best = index; }
          index = full.indexOf(text, index + 1);
        }
        if (best === -1) { return null; }
        return { nodes: nodes, starts: starts, start: best, end: best + text.length };
      }

      function wrap(found, id, color) {
        const marks = [];
        for (let i = 0; i < found.nodes.length; i++) {
          let node = found.nodes[i];
          const start = found.starts[i];
          const end = start + node.data.length;
          if (end <= found.start || start >= found.end) { continue; }
          const parent = node.parentNode;
          if (!parent || /^(script|style|title)$/i.test(parent.nodeName)) { continue; }
          const from = Math.max(found.start - start, 0);
          const to = Math.min(found.end - start, node.data.length);
          if (to <= from) { continue; }
          if (from > 0) { node = node.splitText(from); }
          if (to - from < node.data.length) { node.splitText(to - from); }
          const mark = document.createElement('mark');
          mark.className = 'lumen-hl';
          mark.dataset.id = id;
          mark.style.setProperty('--lumen-hl', color);
          node.parentNode.insertBefore(mark, node);
          mark.appendChild(node);
          marks.push(mark);
        }
        return marks;
      }

      function clearMarks() {
        for (const mark of Array.from(document.querySelectorAll('mark.lumen-hl'))) {
          const parent = mark.parentNode;
          while (mark.firstChild) { parent.insertBefore(mark.firstChild, mark); }
          parent.removeChild(mark);
          parent.normalize();
        }
      }

      let selectionTimer = null;
      document.addEventListener('selectionchange', () => {
        clearTimeout(selectionTimer);
        selectionTimer = setTimeout(() => {
          const selection = window.getSelection();
          if (!selection || selection.rangeCount === 0 || selection.isCollapsed) {
            post({ type: 'selection', text: '' });
            return;
          }
          const range = selection.getRangeAt(0);
          const raw = range.toString();
          const text = selection.toString().trim();
          if (!text) { post({ type: 'selection', text: '' }); return; }
          post({
            type: 'selection',
            text: text,
            raw: raw,
            offset: offsetOf(range.startContainer, range.startOffset),
            label: labelOf(range.startContainer),
            progression: progression()
          });
        }, 250);
      });

      // Якоря оглавления в этой главе: по ним видно, в каком разделе сейчас читатель.
      let anchors = [];
      function currentAnchor() {
        let current = null;
        for (const id of anchors) {
          const element = document.getElementById(id);
          if (!element) { continue; }
          if (element.getBoundingClientRect().top <= 120) { current = id; } else { break; }
        }
        return current;
      }

      let scrollTimer = null;
      window.addEventListener('scroll', () => {
        clearTimeout(scrollTimer);
        scrollTimer = setTimeout(() => post({ type: 'scroll', progression: progression(), anchor: currentAnchor() }), 150);
      }, { passive: true });

      document.addEventListener('click', (event) => {
        const mark = event.target.closest ? event.target.closest('mark.lumen-hl') : null;
        if (mark && window.getSelection().isCollapsed) {
          post({ type: 'highlightTap', id: mark.dataset.id });
        }
      });

      window.lumen = {
        setStyle: (css) => { style.textContent = css; },
        scrollTo: (value) => {
          const max = document.documentElement.scrollHeight - window.innerHeight;
          window.scrollTo(0, Math.max(max, 0) * value);
        },
        paint: (items) => {
          clearMarks();
          const missing = [];
          for (const item of items) {
            const found = locate(item.text, item.offset || 0);
            if (!found || wrap(found, item.id, item.color).length === 0) { missing.push(item.id); }
          }
          return missing;
        },
        reveal: (id) => {
          const mark = document.querySelector('mark.lumen-hl[data-id="' + id + '"]');
          if (!mark) { return false; }
          mark.scrollIntoView({ block: 'center' });
          const marks = document.querySelectorAll('mark.lumen-hl[data-id="' + id + '"]');
          marks.forEach((m) => m.classList.add('lumen-flash'));
          setTimeout(() => marks.forEach((m) => m.classList.remove('lumen-flash')), 1600);
          return true;
        },
        clearSelection: () => { window.getSelection().removeAllRanges(); },
        setAnchors: (ids) => {
          anchors = ids;
          post({ type: 'scroll', progression: progression(), anchor: currentAnchor() });
        },
        scrollToAnchor: (id) => {
          const element = document.getElementById(id) || document.querySelector('[name="' + CSS.escape(id) + '"]');
          if (!element) { return false; }
          element.scrollIntoView({ block: 'start' });
          window.scrollBy(0, -16);
          return true;
        },
        // Заголовки главы для оглавления, если в файле своего нет. Без id им даётся свой.
        headings: () => {
          const result = [];
          let index = 0;
          for (const element of document.body.querySelectorAll('h1, h2, h3')) {
            const title = (element.textContent || '').replace(/\s+/g, ' ').trim();
            if (!title) { continue; }
            index += 1;
            if (!element.id) { element.id = 'lumen-h-' + index; }
            result.push({ id: element.id, title: title, level: Number(element.tagName.substring(1)) - 1 });
          }
          return JSON.stringify(result);
        },
        progression: progression
      };
      post({ type: 'ready', progression: progression() });
    })();
    """#
}

/// Как выглядит текст в читалке: тема страницы и размер шрифта.
public struct ReaderAppearance: Hashable, Sendable {
    public enum Palette: String, CaseIterable, Sendable, Identifiable {
        /// Тёмная закатная тема приложения: текст светлый, фон прозрачный.
        case night
        /// Тёплая бумага для долгого чтения.
        case paper
        /// Розово-персиковая бумага: светлее ночи, теплее бумаги.
        case dawn
        /// Как задумал автор файла, только поля и ширина колонки наши.
        case original

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .night: "Ночь"
            case .paper: "Бумага"
            case .dawn: "Рассвет"
            case .original: "Как в файле"
            }
        }
    }

    /// Шрифт текста книги.
    public enum Typeface: String, CaseIterable, Sendable, Identifiable {
        case serif
        case sans
        case rounded

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .serif: "Засечки"
            case .sans: "Гротеск"
            case .rounded: "Округлый"
            }
        }
    }

    public static let fontSizes = 14...28

    public var palette: Palette
    public var fontSize: Int
    public var typeface: Typeface

    public init(palette: Palette = .night, fontSize: Int = 18, typeface: Typeface = .serif) {
        self.palette = palette
        self.fontSize = min(max(fontSize, Self.fontSizes.lowerBound), Self.fontSizes.upperBound)
        self.typeface = typeface
    }

    /// Фон страницы под текстом. Ночью фон прозрачный: под ним закатный фон приложения.
    public var backgroundHex: UInt32? {
        switch palette {
        case .night: nil
        case .paper: 0xF4EADB
        case .dawn: 0xFBE6DA
        case .original: 0xFFFFFF
        }
    }

    var css: String {
        let font = switch typeface {
        case .serif: "'New York', 'Iowan Old Style', Georgia, 'Times New Roman', serif"
        case .sans: "-apple-system, 'SF Pro Text', 'Helvetica Neue', sans-serif"
        case .rounded: "ui-rounded, 'SF Pro Rounded', -apple-system, sans-serif"
        }
        let layout = """
        html { -webkit-text-size-adjust: 100%; }
        body {
          max-width: 40em; margin: 0 auto !important; padding: 40px 32px 140px !important;
          font-size: \(fontSize)px !important; line-height: 1.62; word-wrap: break-word;
        }
        img, svg, video { max-width: 100% !important; height: auto !important; }
        table { border-collapse: collapse; max-width: 100%; }
        td, th { border: 1px solid rgba(127,127,127,0.35); padding: 6px 10px; vertical-align: top; }
        pre { white-space: pre-wrap; }
        p.empty { margin: 0.4em 0; }
        p.center { text-align: center; }
        p.verse { margin: 0.1em 0 0.1em 2em; }
        p.text-author { text-align: right; font-style: italic; }
        p.image, p.page { text-align: center; }
        section.slide {
          margin: 0 0 28px; padding: 22px 26px 18px; border-radius: 18px; position: relative;
          border: 1px solid rgba(127,127,127,0.28);
        }
        .slide-number { position: absolute; top: 10px; right: 16px; font-size: 12px; opacity: 0.5; }
        mark.lumen-hl {
          background: color-mix(in srgb, var(--lumen-hl) 40%, transparent) !important;
          color: inherit !important; border-radius: 7px; padding: 1px 3px; cursor: pointer;
          -webkit-box-decoration-break: clone; box-decoration-break: clone;
          transition: background 0.4s;
        }
        mark.lumen-hl.lumen-flash { background: color-mix(in srgb, var(--lumen-hl) 75%, transparent) !important; }
        """
        switch palette {
        case .night:
            return layout + """
            html, body { background: transparent !important; color: #F3E3DA !important; }
            body { font-family: \(font) !important; }
            body * { color: inherit !important; background-color: transparent !important; border-color: rgba(255,255,255,0.18) !important; }
            mark.lumen-hl { background: color-mix(in srgb, var(--lumen-hl) 30%, transparent) !important; }
            mark.lumen-hl.lumen-flash { background: color-mix(in srgb, var(--lumen-hl) 62%, transparent) !important; }
            a { color: #FFB38A !important; }
            h1, h2, h3, h4 { color: #FFE3D2 !important; line-height: 1.25; }
            section.slide { background: rgba(255,255,255,0.06) !important; }
            ::selection { background: rgba(255,170,120,0.45); }
            """
        case .paper:
            return layout + """
            html, body { background: #F4EADB !important; color: #3B2E25 !important; }
            body { font-family: \(font) !important; }
            body * { color: inherit !important; background-color: transparent !important; }
            a { color: #B4532A !important; }
            section.slide { background: rgba(255,255,255,0.55) !important; }
            """
        case .dawn:
            return layout + """
            html, body { background: #FBE6DA !important; color: #5B3B3E !important; }
            body { font-family: \(font) !important; }
            body * { color: inherit !important; background-color: transparent !important; }
            a { color: #C0566A !important; }
            h1, h2, h3, h4 { color: #4E2E33 !important; line-height: 1.25; }
            section.slide { background: rgba(255,255,255,0.5) !important; }
            ::selection { background: rgba(240,140,130,0.35); }
            """
        case .original:
            return layout + "html { background: #FFFFFF; } body { color: #111; }"
        }
    }
}
