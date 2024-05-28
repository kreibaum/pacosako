//! This takes a preliminary opening book and then finds connections inside that book.
//! The connections are then stored in a new opening book.
//!
//! We do this by executing every possible action on every position already in the book
//! and figuring out if we end up in the book again. If so, then we have made a connection.
//! This connection gets stored in the book.

