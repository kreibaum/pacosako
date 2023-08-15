use pacosako::PlayerColor;

use super::websocket::SocketId;

pub trait GameProtectionStrategy: Send + Sync {
    fn check_action_allowed(
        self,
        color: PlayerColor,
        socket_id: SocketId,
    ) -> (bool, Box<dyn GameProtectionStrategy>);
}

/// A strategy that allows any action.
pub struct NoProtectionStrategy;

impl GameProtectionStrategy for NoProtectionStrategy {
    fn check_action_allowed(
        self,
        _color: PlayerColor,
        _socket_id: SocketId,
    ) -> (bool, Box<dyn GameProtectionStrategy>) {
        (true, Box::new(self))
    }
}
