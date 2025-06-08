// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;


contract Auction{

    //Ordeno la definición de las variables para economizar slots en la EVM
    bool active = true;                     // 1 byte

    address public seller;                 // 20 bytes 
    address public owner;                 // 20 bytes 

    uint256 public bidGap;                 // 32 bytes
    uint256 public gasCommissionPercentage;

    uint256 public initDate;
    uint256 public finishDate;
    uint256 bidExtensionTime;
    uint256 bidExtensionZone;

    // Estructuras grandes que no se pueden empaquetar
    mapping(address => uint256) bidAddressLastAmount;
    mapping(address => uint256) bidAddressTotalAmount;
    //La estructura de cada apuesta para...
    struct Bid { 
        address bidder;
        uint256 amount;
    }
    //...armar una colección de todas las apuestas.
    Bid[] bids;                     
    Bid winnerBid;                 

    constructor (   uint256 _bidGap, 
                    uint256 _gasCommissionPercentage, 
                    uint256 _durationInMinutes, 
                    uint256 _bidExtensionTimeInMinutes,
                    uint256 _bidExtensionZoneInMinutes,
                    address _seller
                    ){

        seller = _seller;
        owner = msg.sender;
        bidGap = (_bidGap == 0) ? 5 : _bidGap; //Si no se define, pongo por default el 5% de salto entre bids según enunciado.
        gasCommissionPercentage = (_gasCommissionPercentage == 0) ? 2 : _gasCommissionPercentage; //Si no se define, va el 2% según enunciado.
        bidExtensionTime = (_bidExtensionTimeInMinutes == 0) ? 600 : (_bidExtensionTimeInMinutes*60); //Si no se define, va 10 minutos según enunciado.
        bidExtensionZone = (_bidExtensionZoneInMinutes == 0) ? 600 : (_bidExtensionZoneInMinutes*60); //Si no se define, va 10 minutos según enunciado.
        
        require(_durationInMinutes >= 1,"Duration must be at least 1 minute");

        initDate = block.timestamp;
        finishDate = initDate + _durationInMinutes*60;
        
    }

    //----------------------------------------------------------//
    //Obtengo todas las subastas realizadas
    function getWinner() public view isEnded() returns (Bid memory) {
        return winnerBid;
    }

    //Obtengo todas las subastas realizadas
    function getAllBids() public view returns (Bid[] memory) {
        return bids;
    }

    //---------------------------------------------------------//
    function MakeABid () payable isActive() isNotEnded() external {
        
        //Valido que la oferta sea mayor a 0.
        require (msg.value > 0, "The amount must be higher than zero");

        /*
        Como Solidity no maneja decimales, en lugar de dividir para validar, debo multiplicar.
        Ejemplo: Si _amount es 200, maxBidAmount es 150 y bidGap es 5, entonces:
        200*100 >= 150 * (100 + 5)
        20000 >= 15750 --> OK
        */

	    //Valido que el valor sea superior al menos un bidGap% que la oferta ganadora para tomarlo.
        require (msg.value*100 >= winnerBid.amount*(100 + bidGap), "The amount is not higher than the gap");
    
        //Guardo la información de este nuevo postor con su oferta superadora
        bidAddressLastAmount[msg.sender] = msg.value;
        bidAddressTotalAmount[msg.sender] += msg.value;
        bids.push(Bid(msg.sender,msg.value));

        //Actualizo la variable estructurada winnerBid con la info de la oferta superadora.
        winnerBid.amount = msg.value;
        winnerBid.bidder = msg.sender;

        //Emito el evento de que hay una oferta superadora
        emit NewOffer(msg.sender, msg.value);

        //Chequeo si está cerca del final de la subasta y, de ser así, corro la fecha de fin
        if (block.timestamp >= (finishDate-bidExtensionZone))
        {
            finishDate = block.timestamp + bidExtensionTime;
        }

    }  

    event NewOffer(address indexed sender, uint256 value);

    //Valido que la subasta esté vigente
    modifier isNotEnded() {
        //Si aún el tiempo está vigente, no puede terminar la subasta
        require(block.timestamp<finishDate,"The Auction has ended");
        _;
    }

    //---------------------------------------------------------//

        
    function EndAuction () isActive() isEnded() onlyOwner() external {

        active = false;
        uint256 totalAmount = 0;
        uint256 refundAmount = 0;
        address bidder;

        //Recorro la colección de ofertantes
        for (uint i=0; i < bids.length; i++)
        {
        
            bidder = bids[i].bidder; //Cargo el address
            totalAmount = bidAddressTotalAmount[bidder]; //Cargo el monto total acumulado de todas sus ofertas
            
        //Si tiene dinero para transferir, procedo.
        if (totalAmount > 0) 
        {

            bidAddressTotalAmount[bidder] = 0; //Como le transfiero el total, vacío la variable para que no siga entrando (si tuvo diversas pujas, seguiría entrando).
        
            //Verifico si se trata o no del ganador.
            if (bidder != winnerBid.bidder) 
            {
                //si no es el ganador, le devuelvo el dinero descontándole la comisión del gas.
                refundAmount = totalAmount - ((totalAmount*gasCommissionPercentage)/100);
                (bool sent,) = payable(bidder).call{value: refundAmount}(""); //Transfiero
                require(sent, "Failed to refund"); //Si hubo error, revierto.                
            }
            else 
            {
                //si es el ganador, transfiero la totalidad al vendedor.
                (bool sent,) = payable(seller).call{value: totalAmount}(""); //Transfiero
                require(sent, "Failed to tranfer prize"); //Si hubo error, revierto.                
            }
            }

        }

        emit AuctionEnded(winnerBid);
    }

    event AuctionEnded(Bid winnerBid);

    //Defino que la acción sólo pueda realizarla el owner.
    modifier onlyOwner() {
        require(msg.sender == owner, "Only the Owner can end the Auction");
        _;
    }

    //Valido que la subasta esté vigente
    modifier isEnded() {
        //Si aún el tiempo está vigente, no puede terminar la subasta
        require(block.timestamp>finishDate,"The Auction has not ended");
        _;
    }     

    //Valido que la subasta esté vigente
    modifier isActive() {
        require(active==true,"The Auction is not longer active");
        _;
    }  
 
    //---------------------------------------------------------//
    function PartialRefund() external isActive() isNotEnded()  {
        uint256 lastAmount = bidAddressLastAmount[msg.sender];
        uint256 totalAmount = bidAddressTotalAmount[msg.sender];
		
		//Si el monto que tiene acumulado es 0, no hago nada porque significa que no se recibieron ofertas de él/ella
        if (totalAmount == 0)
        {
            revert("No bids were received from you"); 
        }

		//Si la última oferta es igual al acumulado entonces tampoco le devuelvo nada porque significa o que sólo hizo una oferta o que ya se le devolvió de forma parcial anteriormente.
        if (lastAmount == totalAmount)
        {
            revert("There is no partial amount to refund"); 
        }  

		uint256 partialAmount = totalAmount - lastAmount; //El total menos la ultima apuesta es lo que puede recuperar.
        bidAddressTotalAmount[msg.sender] -= partialAmount; //Resto el monto parcial (que se le va a devolver) de su total acumulado, así no puede pedir refund n veces.
        
		//Envío el dinero
        (bool sent,) = payable(msg.sender).call{value: partialAmount}(""); 
        require(sent, "Failed to refund"); //Si hubo error, revierto.

    }

}