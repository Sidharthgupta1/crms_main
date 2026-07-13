const bcrypt = require("bcryptjs");
const db = require("./src/config/db");   // adjust path if needed

async function migrate() {

    await db.connectSecondary();

    const users = await db.querySecondary(
        `SELECT user_id, password_hash
         FROM crms_users`
    );

    for (const user of users) {

        // Skip if already hashed
        if (user.PASSWORD_HASH.startsWith("$2")) {
            continue;
        }

        const hash = await bcrypt.hash(user.PASSWORD_HASH, 10);

        await db.executeWithCommitSecondary(
            `UPDATE crms_users
             SET password_hash=:hash
             WHERE user_id=:id`,
            {
                hash,
                id: user.USER_ID
            }
        );

        console.log(`Updated ${user.USER_ID}`);
    }

    console.log("Migration completed.");
}

migrate().catch(console.error);