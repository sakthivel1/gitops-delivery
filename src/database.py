import psycopg2


def get_db_connection(database_url: str):
    return psycopg2.connect(database_url)


def init_db(database_url: str):
    conn = get_db_connection(database_url)
    cur = conn.cursor()
    cur.execute("""
        CREATE TABLE IF NOT EXISTS transactions (
            id          SERIAL PRIMARY KEY,
            amount      NUMERIC(18, 2) NOT NULL,
            description TEXT NOT NULL DEFAULT '',
            created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )
    """)
    conn.commit()
    conn.close()
