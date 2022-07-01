import re
from coverity.utils import LineBufferedProgressHandler

NUM_STARS = 52

COV_SUBSTATUS_REGEX = re.compile("\[STATUS\]\s+(.+)")
COV_COMMIT_TS_REGEX = re.compile("[-\w\s:]+-\s(.+)")
COV_STAR_REGEX = re.compile("^\s*\*+\s*$")

def count_stars(string):
    return sum([len(line.strip()) for line in string.split("\n") if COV_STAR_REGEX.match(line)])


class CovBuildProgressHandler(LineBufferedProgressHandler):
    INC = 100 / float(NUM_STARS)

    def __init__(self, d, outfile=None, otherargs=None):
        super().__init__(d, outfile)
        self._c = 0

        task = d.getVar("BB_RUNTASK")

        self._trigger_word = d.getVarFlag(task, "covprogress-triggerword")
        indet = d.getVarFlag(task, "covprogress-indeterminate")
        self._commit_substatus = not not d.getVarFlag(task, "covprogress-commitsubstatus")

        if self._trigger_word and indet:
            bb.fatal("Task cannot use both covprogress-triggerword and covprogress-indeterminate")

        self._active = False
        if not self._trigger_word and not indet:
            self._active = True
            self._fire_progress(0)
        self._substatus = None

    def handle_line(self, string):
        substatus = COV_SUBSTATUS_REGEX.match(string)
        if substatus:
            self._substatus = substatus.group(1).strip()
            if self._commit_substatus:
                commit_substatus = COV_COMMIT_TS_REGEX.match(self._substatus)
                if commit_substatus:
                    self._substatus = commit_substatus.group(1)

        if not self._active and self._trigger_word:
            if self._trigger_word in string:
                self._active = True
                self.update(0, rate=self._substatus)

        stars = count_stars(string)
        if stars:
            if self._active:
                self._c += type(self).INC * stars
                self.update(self._c, rate=self._substatus)
            else:
                self.update(-stars, rate=self._substatus)
