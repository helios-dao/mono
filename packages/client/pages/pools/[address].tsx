import { POOLS, USDC_ADDRESS } from "src/constants";
import { useEffect, useState } from "react";
import { useRouter } from "next/router";
import abi from "contracts";
import formatUsdc from "src/utils/formatUsdc";
import InvestForm from "@components/pools/InvestForm";
import Link from "next/link";
import useContract from "src/hooks/useContract";
import UserParticipation from "@components/pools/UserParticipation";
import WalletWrapper from "@components/WalletWrapper";

export default function PoolPage() {
  const router = useRouter();
  const params = router.query;
  const [pool, setPool] = useState(null);
  const [isLoading, setIsLoading] = useState(true);
  const poolContract = useContract(params.address, abi.pool);
  const usdcToken = useContract(USDC_ADDRESS, abi.usdc);

  useEffect(() => {
    const pool = POOLS.find((pool) => params.address === pool.address);
    setPool(pool);
  }, []);

  useEffect(() => {
    if (pool !== null) setIsLoading(false);
  }, [pool]);

  useEffect(() => {
    fetchPool();
  }, [poolContract, usdcToken]);

  const fetchPool = async () => {
    if (!poolContract || !usdcToken) return;

    const totalParticipation = await usdcToken.balanceOf(
      await poolContract.liquidityLocker(),
    );
    setPool({
      ...pool,
      participation: formatUsdc(totalParticipation.toString()),
    });
  };

  if (isLoading) return <div></div>;

  if (!pool) return <div>Could not find pool</div>;

  return (
    <>
      <div>
        <Link href="/">
          <a>&larr; Home</a>
        </Link>
      </div>
      <div>{pool.name}</div>
      <div>Total participation: ${pool.participation || "??"}</div>
      <WalletWrapper>
        <UserParticipation pool={pool} />
        <InvestForm pool={pool} />
      </WalletWrapper>
    </>
  );
}
