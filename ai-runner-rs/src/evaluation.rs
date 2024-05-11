/// Given a DenseBoard, we want to turns this into a model evaluation.
/// This is a list of the relative policy for various legal actions.
/// This also returns the value, but the raw Hedwig value isn't very good.
/// The action values have been normalized to sum up to 1.
#[derive(Debug)]
pub struct ModelEvaluation {
    pub value: f32,
    pub policy: Vec<(pacosako::PacoAction, f32)>,
}

impl ModelEvaluation {
    pub(crate) fn normalize_policy(&mut self) {
        let sum: f32 = self.policy.iter().map(|(_, p)| p).sum();
        if sum == 0. {
            if !self.policy.is_empty() {
                let spread = 1. / self.policy.len() as f32;
                for (_, p) in &mut self.policy {
                    *p = spread;
                }
            }
            return;
        }
        for (_, p) in &mut self.policy {
            *p /= sum;
        }
    }
}
