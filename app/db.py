from psycopg_pool import AsyncConnectionPool


def make_pool(dsn: str) -> AsyncConnectionPool:
    # open=False: opening in the constructor is deprecated and blocks startup.
    return AsyncConnectionPool(dsn, min_size=1, max_size=5, open=False)


async def ping(pool: AsyncConnectionPool) -> str:
    async with pool.connection() as conn:
        cur = await conn.execute("select version()")
        row = await cur.fetchone()
        return row[0].split(",")[0]