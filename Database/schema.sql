PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS schema_meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS papers (
  paper_id TEXT PRIMARY KEY,
  source TEXT NOT NULL,
  year INTEGER,
  province TEXT NOT NULL DEFAULT '',
  exam_level TEXT NOT NULL DEFAULT '',
  paper_name TEXT NOT NULL,
  license_note TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS materials (
  material_id TEXT PRIMARY KEY,
  paper_id TEXT,
  source_material_id TEXT,
  title TEXT NOT NULL DEFAULT '',
  body TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY (paper_id) REFERENCES papers(paper_id)
);

CREATE TABLE IF NOT EXISTS material_images (
  image_id TEXT PRIMARY KEY,
  material_id TEXT NOT NULL,
  relative_path TEXT NOT NULL,
  media_type TEXT NOT NULL DEFAULT '',
  sort_order INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY (material_id) REFERENCES materials(material_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS questions (
  question_id TEXT PRIMARY KEY,
  source_question_id TEXT,
  source TEXT NOT NULL,
  paper_id TEXT,
  material_id TEXT,
  subject TEXT NOT NULL,
  type_name TEXT NOT NULL,
  question_type TEXT NOT NULL,
  stem TEXT NOT NULL,
  stem_hash TEXT NOT NULL,
  explanation TEXT NOT NULL DEFAULT '',
  year INTEGER,
  province TEXT NOT NULL DEFAULT '',
  paper_name TEXT NOT NULL DEFAULT '',
  license_note TEXT NOT NULL,
  review_status TEXT NOT NULL,
  review_reasons TEXT NOT NULL DEFAULT '[]',
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (paper_id) REFERENCES papers(paper_id),
  FOREIGN KEY (material_id) REFERENCES materials(material_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_questions_source_qid
ON questions(source, source_question_id)
WHERE source_question_id IS NOT NULL AND source_question_id != '';

CREATE INDEX IF NOT EXISTS idx_questions_stem_hash ON questions(stem_hash);
CREATE INDEX IF NOT EXISTS idx_questions_practice
ON questions(review_status, subject, sort_order);

CREATE TABLE IF NOT EXISTS options (
  question_id TEXT NOT NULL,
  option_key TEXT NOT NULL,
  option_text TEXT NOT NULL,
  sort_order INTEGER NOT NULL,
  PRIMARY KEY (question_id, option_key),
  FOREIGN KEY (question_id) REFERENCES questions(question_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS answer_keys (
  question_id TEXT NOT NULL,
  option_key TEXT NOT NULL,
  sort_order INTEGER NOT NULL,
  PRIMARY KEY (question_id, option_key),
  FOREIGN KEY (question_id) REFERENCES questions(question_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS question_images (
  image_id TEXT PRIMARY KEY,
  question_id TEXT NOT NULL,
  role TEXT NOT NULL,
  relative_path TEXT NOT NULL,
  media_type TEXT NOT NULL DEFAULT '',
  sort_order INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY (question_id) REFERENCES questions(question_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS attempts (
  attempt_id TEXT PRIMARY KEY,
  question_id TEXT NOT NULL,
  session_id TEXT,
  is_correct INTEGER NOT NULL,
  answered_at TEXT NOT NULL,
  FOREIGN KEY (question_id) REFERENCES questions(question_id)
);

CREATE INDEX IF NOT EXISTS idx_attempts_question ON attempts(question_id, answered_at);

CREATE TABLE IF NOT EXISTS attempt_choices (
  attempt_id TEXT NOT NULL,
  option_key TEXT NOT NULL,
  PRIMARY KEY (attempt_id, option_key),
  FOREIGN KEY (attempt_id) REFERENCES attempts(attempt_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS practice_sessions (
  session_id TEXT PRIMARY KEY,
  mode TEXT NOT NULL,
  subject TEXT NOT NULL DEFAULT '',
  started_at TEXT NOT NULL,
  submitted_count INTEGER NOT NULL DEFAULT 0,
  correct_count INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS import_batches (
  batch_id TEXT PRIMARY KEY,
  source_file TEXT NOT NULL DEFAULT '',
  started_at TEXT NOT NULL,
  finished_at TEXT,
  status TEXT NOT NULL,
  inserted_count INTEGER NOT NULL DEFAULT 0,
  updated_count INTEGER NOT NULL DEFAULT 0,
  duplicate_source_count INTEGER NOT NULL DEFAULT 0,
  duplicate_stem_count INTEGER NOT NULL DEFAULT 0,
  needs_review_count INTEGER NOT NULL DEFAULT 0,
  ready_count INTEGER NOT NULL DEFAULT 0,
  report_json TEXT NOT NULL DEFAULT ''
);
