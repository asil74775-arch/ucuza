import os
import tempfile

_tmp = tempfile.mkdtemp()
os.environ["DATABASE_URL"] = f"sqlite+aiosqlite:///{_tmp}/test.db"
os.environ["MEDIA_ROOT"] = f"{_tmp}/media"
os.environ["GEMINI_API_KEY"] = ""
os.environ["SERPAPI_KEY"] = ""
os.environ["YOUTUBE_API_KEY"] = ""
