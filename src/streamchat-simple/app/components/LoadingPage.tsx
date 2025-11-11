import ClockLoader from "react-spinners/ClockLoader";

const LoadingPage = () => {
  return (
    <>
      <div className="flex flex-col h-screen">
        <div className="flex grow justify-center items-center">
          <ClockLoader size={100} />
        </div>
      </div>
    </>
  );
};

export default LoadingPage;
