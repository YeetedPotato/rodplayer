import tempfile
import unittest
from pathlib import Path

from apply_native_hosts import patch_windows_title


class PatchWindowsTitleTest(unittest.TestCase):
    def test_rebrands_generated_window_title_and_is_idempotent(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            main_cpp = root / "windows" / "runner" / "main.cpp"
            main_cpp.parent.mkdir(parents=True)
            main_cpp.write_text('window.Create(L"rodplayer", origin, size);\n')

            patch_windows_title(root)
            patch_windows_title(root)

            self.assertEqual(
                main_cpp.read_text(),
                'window.Create(L"Nautilus", origin, size);\n',
            )

    def test_rejects_unrecognized_generated_title(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            main_cpp = root / "windows" / "runner" / "main.cpp"
            main_cpp.parent.mkdir(parents=True)
            main_cpp.write_text('window.Create(L"other", origin, size);\n')

            with self.assertRaisesRegex(
                RuntimeError, "expected one generated Windows window title"
            ):
                patch_windows_title(root)


if __name__ == "__main__":
    unittest.main()
