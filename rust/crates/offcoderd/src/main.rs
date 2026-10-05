//! offcoderd binary: production leader daemon. See lib.rs for the router.

#[tokio::main]
async fn main() {
    offcoderd::run().await;
}
