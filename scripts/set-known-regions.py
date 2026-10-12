"""XcodeGen 2.46은 knownRegions 옵션이 없고, syncedFolder 안은 지역을 훑지 않는다."""
import re
from pathlib import Path

path = Path("DFlight.xcodeproj/project.pbxproj")
text = path.read_text()
updated, count = re.subn(
    r"knownRegions = \([^)]*\);",
    "knownRegions = (\n\t\t\t\tko,\n\t\t\t\tja,\n\t\t\t\ten,\n\t\t\t);",
    text,
    count=1,
)
if count != 1:
    raise SystemExit("knownRegions block not found")
path.write_text(updated)
