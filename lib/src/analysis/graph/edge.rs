use crate::PacoAction;

pub trait EdgeData {
    fn init(action: PacoAction, from_hash: u64) -> Self;
    fn update(&mut self, action: PacoAction, from_hash: u64);
    fn first(&self) -> (PacoAction, u64);
}

/// Edge data that only tracks the first edge
#[derive(Debug)]
pub struct FirstEdge {
    pub action: PacoAction,
    pub from_hash: u64,
}

impl EdgeData for FirstEdge {
    fn init(action: PacoAction, from_hash: u64) -> Self {
        Self { action, from_hash }
    }
    fn update(&mut self, _action: PacoAction, _from_hash: u64) {
        // Nothing to do, we only track the first edge.
    }
    fn first(&self) -> (PacoAction, u64) {
        (self.action, self.from_hash)
    }
}

#[derive(Debug)]
pub struct OrderedEdges(pub Vec<(PacoAction, u64)>);

impl EdgeData for OrderedEdges {
    fn init(action: PacoAction, from_hash: u64) -> Self {
        Self(vec![(action, from_hash)])
    }
    fn update(&mut self, action: PacoAction, from_hash: u64) {
        self.0.push((action, from_hash));
    }

    fn first(&self) -> (PacoAction, u64) {
        self.0[0]
    }
}