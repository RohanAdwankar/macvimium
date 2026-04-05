from __future__ import annotations

import re
import subprocess
import time
from pathlib import Path

import chess
import chess.engine

ROOT = Path(__file__).resolve().parents[1]
MACLICK = ROOT / ".build" / "debug" / "maclick"
WINDOW = "Chess"
ENGINE_PATH = "/opt/homebrew/bin/stockfish"

HINT_RE = re.compile(r"^maclick: hint ([A-Z]+) -> (.+)$")
TITLE_RE = re.compile(r"^maclick: showing \d+ hints for .+ \| (.+)$")
SQUARE_RE = re.compile(r"\b([a-h][1-8])\b")
PIECE_RE = re.compile(r"^(white|black) (king|queen|rook|bishop|knight|pawn), ([a-h][1-8])$")

PIECE_SYMBOLS = {
    ("white", "king"): "K",
    ("white", "queen"): "Q",
    ("white", "rook"): "R",
    ("white", "bishop"): "B",
    ("white", "knight"): "N",
    ("white", "pawn"): "P",
    ("black", "king"): "k",
    ("black", "queen"): "q",
    ("black", "rook"): "r",
    ("black", "bishop"): "b",
    ("black", "knight"): "n",
    ("black", "pawn"): "p",
}


def run_maclick(*args: str) -> str:
    result = subprocess.run(
        [str(MACLICK), *args],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout


def inspect() -> tuple[str, dict[str, str], dict[str, str]]:
    output = run_maclick(WINDOW, "--help")
    title_match = TITLE_RE.match(output.splitlines()[0].strip())
    if not title_match:
        raise RuntimeError(f"unexpected help header: {output.splitlines()[0]}")

    pieces: dict[str, str] = {}
    square_to_label: dict[str, str] = {}

    for line in output.splitlines()[1:]:
        match = HINT_RE.match(line.strip())
        if not match:
            continue

        label, description = match.groups()
        content = description.removeprefix("AXButton: ").removeprefix("AXMenuButton: ").strip()
        piece_match = PIECE_RE.match(content)
        if piece_match:
            color, piece_name, square = piece_match.groups()
            pieces[square] = PIECE_SYMBOLS[(color, piece_name)]
            square_to_label[square] = label
            continue

        square_match = SQUARE_RE.search(content)
        if square_match:
            square_to_label[square_match.group(1)] = label

    return title_match.group(1), pieces, square_to_label


def board_signature(board: chess.Board) -> dict[str, str]:
    signature: dict[str, str] = {}
    for square, piece in board.piece_map().items():
        signature[chess.square_name(square)] = piece.symbol()
    return signature


def build_board(pieces: dict[str, str], white_to_move: bool) -> chess.Board:
    board = chess.Board(None)
    for square_name, symbol in pieces.items():
        board.set_piece_at(chess.parse_square(square_name), chess.Piece.from_symbol(symbol))
    board.turn = chess.WHITE if white_to_move else chess.BLACK

    castling = ""
    if pieces.get("e1") == "K" and pieces.get("h1") == "R":
        castling += "K"
    if pieces.get("e1") == "K" and pieces.get("a1") == "R":
        castling += "Q"
    if pieces.get("e8") == "k" and pieces.get("h8") == "r":
        castling += "k"
    if pieces.get("e8") == "k" and pieces.get("a8") == "r":
        castling += "q"
    board.set_castling_fen(castling or "-")
    board.ep_square = None
    board.halfmove_clock = 0
    board.fullmove_number = 1
    return board


def wait_for_board_change(current: chess.Board, timeout: float = 15.0) -> tuple[str, dict[str, str], dict[str, str]]:
    deadline = time.time() + timeout
    current_signature = board_signature(current)
    while time.time() < deadline:
        title, pieces, square_to_label = inspect()
        if pieces != current_signature:
            return title, pieces, square_to_label
        time.sleep(0.5)
    raise TimeoutError("board did not change in time")


def wait_for_exact_board(expected: chess.Board, timeout: float = 10.0) -> tuple[str, dict[str, str], dict[str, str]]:
    deadline = time.time() + timeout
    expected_signature = board_signature(expected)
    while time.time() < deadline:
        title, pieces, square_to_label = inspect()
        if pieces == expected_signature:
            return title, pieces, square_to_label
        time.sleep(0.5)
    raise TimeoutError("expected board state did not appear")


def click_square(label: str) -> None:
    run_maclick(WINDOW, label)


def perform_move(move: chess.Move, square_to_label: dict[str, str]) -> None:
    source = chess.square_name(move.from_square)
    destination = chess.square_name(move.to_square)
    click_square(square_to_label[source])
    time.sleep(0.5)
    click_square(square_to_label[destination])


def execute_move_and_confirm(
    current: chess.Board,
    move: chess.Move,
    square_to_label: dict[str, str],
    attempts: int = 3,
) -> tuple[str, dict[str, str], dict[str, str]]:
    starting_signature = board_signature(current)
    expected = current.copy(stack=False)
    expected.push(move)

    latest_labels = square_to_label
    for attempt in range(attempts):
        perform_move(move, latest_labels)
        try:
            return wait_for_exact_board(expected, timeout=8.0)
        except TimeoutError:
            title, pieces, latest_labels = inspect()
            if pieces == starting_signature and attempt + 1 < attempts:
                time.sleep(0.5)
                continue
            raise RuntimeError(
                f"move {move.uci()} did not reach expected state; last title: {title}"
            )

    raise RuntimeError(f"move {move.uci()} failed after retries")


def match_observed_move(board: chess.Board, observed_pieces: dict[str, str]) -> chess.Move | None:
    for move in board.legal_moves:
        candidate = board.copy(stack=False)
        candidate.push(move)
        if board_signature(candidate) == observed_pieces:
            return move
    return None


def main() -> int:
    title, pieces, square_to_label = inspect()
    board = build_board(pieces, white_to_move="White to Move" in title)

    with chess.engine.SimpleEngine.popen_uci(ENGINE_PATH) as engine:
        for ply in range(80):
            if board.is_game_over():
                print(f"game over before move: {board.outcome()}")
                return 0

            if not board.turn:
                raise RuntimeError("script expects to play White")

            result = engine.play(board, chess.engine.Limit(time=0.05))
            move = result.move
            print(f"white move {ply + 1}: {move.uci()}")
            title, pieces, square_to_label = execute_move_and_confirm(board, move, square_to_label)
            board.push(move)
            print(f"confirmed white move: {title}")

            if board.is_game_over():
                print(f"game over after white move: {board.outcome()}")
                return 0

            title, pieces, square_to_label = wait_for_board_change(board)
            reply = match_observed_move(board, pieces)
            if reply is None:
                raise RuntimeError(f"could not match opponent move from state: {title}")
            board.push(reply)
            print(f"black reply: {reply.uci()} | {title}")

        raise RuntimeError("reached move limit without a conclusive result")


if __name__ == "__main__":
    raise SystemExit(main())
