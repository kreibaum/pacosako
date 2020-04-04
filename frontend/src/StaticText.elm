module StaticText exposing
    ( blogEditorExampleText
    , initArticleTitle
    , mainPageGreetingText
    , witness
    )


mainPageGreetingText : String
mainPageGreetingText =
    """# A tool collection for Paco Ŝako

Paco Ŝako is a new form of chess created to be an expression of peace, friendship and collaboration, designed with an exciting gameplay. This website hosts some tools to help us communicate about Paco Ŝako.

## Designing positions

The Feature that is currently best developed is the position editor. Here you can arrange Paco Ŝako pieces as you please and export the result as an image. You can download it as a png file for easy sharing, or download a raw SVG file that you can edit later.

<puzzle data=".. .K .. .. .. .. BP ..
PN .. N. .. PP .. .. ..
.P .. RP .. .. NQ .. ..
.. .. .B BR P. QN PB ..
RP K. P. .. .P .. .. ..
P. P. .. .. .. .P .. ..
.. .. .P .. .. .. .. ..
.. .. .. .. .. .. PR .."/>

If you want some more examples, check out the *Library* page!

If you want to store the positions you have designed in the editor, you will need to log in. There is no sign up system at the moment, so you will need to ask Rolf to create an account for you. As a workaround, there is also a text export that you can use to save to a position.

### Analysing positions

I already have a tool which can perform ŝako analysis on a given position, this is developed in the [Paco Ŝako Rust](https://github.com/roSievers/pacosako-rust) project. Eventually, this functionality will be integrated into the position editor.

## Writing about Paco Ŝako

The tool collection now also includes a *Blog Editor* that you can use to write texts on Paco Ŝako. The nice thing about this editor is, that you can directly embed positions from the editor into the text.

Note that even with a user account, the content you edit in the Blog editor can not be saved yet. Please make sure to save your texts in a text file."""


initArticleTitle : String
initArticleTitle =
    "Markdown editor with Paco Ŝako support"


blogEditorExampleText : String
blogEditorExampleText =
    """There are many details about Paco Ŝako that I would love to discuss. Having a way to write and share articles on Paco Ŝako online would greatly contribute this. In this editor you can use [Github flavored Markdown](https://guides.github.com/features/mastering-markdown/) to write articles on Paco Ŝako.

You can use a `<puzzle data="..">` tag to render a Paco Ŝako position. Just copy the "Text notation you can store" from the Position editor into the Blog editor.

<puzzle data=".. R. .. RR .. .. QQ ..
.. .. .. .. PB .. .P P.
.. .. PP .. .. .N .. ..
K. .. .P .. .P NP B. ..
P. .. .. .. .P PP .. P.
.R .. P. .. .. .. .K ..
B. .P .. .. .. .. N. ..
.. .. .. .. .N .. .. PB"/>

Note that even with a user account, the content you edit in the Blog editor can not be saved yet. Please make sure to save your texts in a text file.

```
Code blocks are also supported.
But they don't have any syntax highlighting :(
```

Code blocks will be useful when we communicate about the internals of this website."""


witness : String
witness =
    """# Witnessing Ŝako

In mathematical logic, a [witness](<https://en.wikipedia.org/wiki/Witness_(mathematics)>) is a specific value `t` to be substituted for variable `x` of an existential statement of the form `there exists x with phi(x)` such that `phi(t)` is true. I believe we can use this concept to efficiently reasoning about Paco Ŝako positions.

Some basic definitions:

* An *action* can be lifting a piece (or union), placing a piece (or union) or promoting a piece.
* A *move* is a sequence of actions.
* A *legal move* is a move that is permitted by the rules of Paco Ŝako.
* Note that all legal moves leave the board in a *settled* position, this is a position where all pieces have a position on the board and no piece is lifted.

I will, without loss of generality, describe some definitions only for a single player. The symmetric definition holds for the other player.

The black player is in *Ŝako*, when there exists a *legal move* for white that ends with the black king in a union. Such a move is called a *Ŝako witness* for white. A move that does not end with the black player in a union or is not legal, is not a witness.

Checking whether a move constitutes a Ŝako witness can be easily done by checking
legality of the move. I have already implemented a function in my `pacosako-rust` library that returns all Ŝako witnesses for a given position.

```
type alias Move : List Action

isLegal : Color -> Position -> Move -> Boolean

isWitness : Color -> Position -> Move -> Boolean

determineSako : Color -> Position -> List Move
```

Please note that we don't have a `Witness` type as this is just a subtype of `Move`. While some programming languages may represent this as a [refinement type](https://en.wikipedia.org/wiki/Refinement_type) I am not doing this.

The `determineSako` function is actually quite simple:

```
-- This function is itself build on a legalActions function. The implementation
-- of legalMoves builds a graph, eliminates cycles and the finds all paths.
legalMoves : Color -> Position -> List Move

determineSako color position =
    legalMoves color position
        |> List.filter (isWitness color position)
```

## Mate

The black player is in *mate* (also called in *Paco Ŝako*), when

1. they are in Ŝako,
2. the white player is not in Ŝako,
3. each legal move they can execute still results in a position where they are in Ŝako.

I do not have an implementation for `determineMate` yet, but it may be a good way to start by working out what it should return.
"""
