from abc import ABC, abstractmethod
from bb.progress import ProgressHandler
from io import StringIO


class LineBufferedProgressHandler(ProgressHandler, ABC):
    def __init__(self, d, outfile=None, otherargs=None):
        super().__init__(d, outfile)
        self._buffer = StringIO()
        self._l = 0

        self._fire_progress(0)

    @abstractmethod
    def handle_line(self, line):
        pass

    def write(self, string):
        # Buffer the output so we can process it line by line
        p = self._buffer.tell()
        self._buffer.write(string)
        self._buffer.seek(p)

        for line in self._buffer:
            self.handle_line(line)

        super().write(string)

