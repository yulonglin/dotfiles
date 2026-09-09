pub enum ListItem {
    GroupHeader { name: String },
    Component { name: String, description: String, selected: bool },
}

pub struct AppState {
    pub items: Vec<ListItem>,
    pub cursor: usize,
    pub confirmed: bool,
    pub cancelled: bool,
    /// `--single`: Enter picks the row under the cursor and nothing else.
    pub single: bool,
}

impl AppState {
    pub fn new(items: Vec<ListItem>, single: bool) -> Self {
        let first_component = items.iter()
            .position(|i| matches!(i, ListItem::Component { .. }))
            .unwrap_or(0);

        AppState {
            items,
            cursor: first_component,
            confirmed: false,
            cancelled: false,
            single,
        }
    }

    pub fn toggle(&mut self) {
        if let Some(ListItem::Component { selected, .. }) = self.items.get_mut(self.cursor) {
            *selected = !*selected;
        }
    }

    /// Single-select: the cursor row becomes the only selected item.
    pub fn select_cursor_only(&mut self) {
        let cursor = self.cursor;
        for (i, item) in self.items.iter_mut().enumerate() {
            if let ListItem::Component { selected, .. } = item {
                *selected = i == cursor;
            }
        }
    }

    pub fn move_down(&mut self) {
        let len = self.items.len();
        let mut next = self.cursor + 1;
        while next < len {
            if matches!(self.items[next], ListItem::Component { .. }) {
                self.cursor = next;
                return;
            }
            next += 1;
        }
        // Wrap around
        for (i, item) in self.items.iter().enumerate() {
            if matches!(item, ListItem::Component { .. }) {
                self.cursor = i;
                return;
            }
        }
    }

    pub fn move_up(&mut self) {
        if self.cursor == 0 { return; }
        let mut prev = self.cursor - 1;
        loop {
            if matches!(self.items[prev], ListItem::Component { .. }) {
                self.cursor = prev;
                return;
            }
            if prev == 0 { break; }
            prev -= 1;
        }
        // Wrap around
        for (i, item) in self.items.iter().enumerate().rev() {
            if matches!(item, ListItem::Component { .. }) {
                self.cursor = i;
                return;
            }
        }
    }

    pub fn selected_count(&self) -> usize {
        self.items.iter().filter(|i| matches!(i, ListItem::Component { selected: true, .. })).count()
    }

    pub fn selected_names(&self) -> Vec<String> {
        self.items.iter()
            .filter_map(|item| {
                if let ListItem::Component { name, selected: true, .. } = item {
                    Some(name.clone())
                } else {
                    None
                }
            })
            .collect()
    }
}
